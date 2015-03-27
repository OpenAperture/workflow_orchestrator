require Logger

defmodule CloudOS.WorkflowOrchestrator.Workflow do
  alias CloudOS.WorkflowOrchestrator.Configuration

  alias CloudOS.WorkflowOrchestrator.Notifications.Publisher, as: NotificationsPublisher

  alias CloudOS.WorkflowOrchestrator.Builder.DockerHostResolver
  alias CloudOS.WorkflowOrchestrator.Builder.Publisher, as: BuilderPublisher
  alias CloudOS.WorkflowOrchestrator.Deployer.Publisher, as: DeployerPublisher
  alias CloudOS.WorkflowOrchestrator.Deployer.EtcdClusterConnectionOptionsResolver

  alias CloudOS.ManagerAPI.EtcdCluster
  alias CloudOS.ManagerAPI.MessagingExchange

	def start_link(workflow_info, delivery_tag) do
		:gen_fsm.start_link(__MODULE__, %{workflow_info: workflow_info, delivery_tag: delivery_tag}, [])
	end

	def init(resolved_state) do
		{:ok, :execute_next_workflow_step, resolved_state}
	end

	def terminate(status, state_name, state) do
		IO.puts("Workflow State Machine has finished")
		:ok
	end

	def handle_event(:stop, state_name, state) do
    {:stop, :normal, state}
  end

	def execute_next_workflow_step(event, from, state) do
    workflow_info = state[:workflow_info]

		current_step = workflow_info[:current_step]
    if current_step == nil do
      resolved_workflow_info = send_success_notification(workflow_info, "Starting workflow...")
    else
      step_time = workflow_info[:step_time]
      timestamp = CloudosBuildServer.Timex.Extensions.get_elapased_timestamp(step_time)
      if (step_time != nil) do
        resolved_workflow_info = Map.delete(workflow_info, :step_time)
      end

      workflow_step_durations = resolved_workflow_info[:workflow_step_durations]
      if (workflow_step_durations != nil) do
        resolved_workflow_info = Map.delete(resolved_workflow_info, :workflow_step_durations)
      else
        workflow_step_durations = %{}
      end
      workflow_step_durations = Map.put(workflow_step_durations, "#{inspect current_step}", timestamp)
      resolved_workflow_info = Map.merge(resolved_workflow_info, %{workflow_step_durations: workflow_step_durations})

      resolved_workflow_info = send_success_notification(resolved_workflow_info, "Completed Workflow Milestone:  #{inspect current_step}, in #{timestamp}")
    end

    resolved_workflow_info = Map.merge(resolved_workflow_info, %{step_time: Time.now()})
    flush_to_database(resolved_workflow_info)

    next_workflow_step = resolve_next_step(resolved_workflow_info)
    if next_workflow_step == nil do
    	next_workflow_step = :workflow_completed
    end
    #execute_workflow_step(resolve_next_step(resolved_state), resolved_state)

		#{:reply, reply, new state, new state data}
    state = Map.put(state, workflow_info: resolved_workflow_info)
		{:reply, :ok, next_workflow_step, state}
	end

	def send_success_notification(state, message) do
		send_notification(state, true, message)
	end

	def send_failure_notification(state, message) do
		send_notification(state, false, message)
	end

	defp send_notification(state, is_success, message) do
		prefix = "[CloudOS Build Server][CloudOS Workflow][#{state[:workflow_id]}]"
    Logger.debug("#{prefix} #{message}")
    #resolved_state = add_event_to_log(state, message, prefix)
    resolved_state = state
    NotificationsPublisher.hipchat_notification(is_success, prefix, message)
    resolved_state
	end

	def flush_to_database(state) do
		#TODO:  placeholder
		:ok	    
  end

  @doc """
  Method to determine the next workflow step, based on the current state of the workflow

  ## Options

  The `state` option is the current state (GenServer) of the workflow

  ## Return Values

  The atom containing the next available state or nil
  """
  @spec resolve_next_step(term) :: term
  def resolve_next_step(state) do
    workflow_info = state[:workflow_info]
  	current_step = workflow_info[:current_step]
  	{_, next_step} = Enum.reduce workflow_info[:workflow_steps], {false, nil}, fn(available_step, {use_next_step, next_step})->
  		#we already found the next step
  		if (next_step != nil) do
  			{false, next_step}
  		else
  			#we're just starting the workflow
				if (current_step == nil) do
  				{false, available_step}
  			else
  				if (use_next_step) do
  					{false, available_step}
  				else
	  				#the current item in the list is the current workflow step
	  				if (current_step == available_step) do
	  					{true, next_step}
	  				else
	  					#the current item in the list is NOT the current workflow step
	  					{false, next_step}
	  				end
	  			end
  			end
  		end
  	end

  	next_step
  end

  @doc """
  Method to fail a workflow step
  ## Options
  The `reason` option defines a String containing the reason the step failed
  The `state` option represents the server's current state
  ## Return Values
  The updated server state
  """
  @spec workflow_step_failed(String.t(), Map) :: Map
  def workflow_step_failed(reason, state) do
    current_step = state[:current_step]
    #resolved_state = send_failure_notification(state, "Workflow Milestone Failed:  #{inspect current_step}.  Reason:  #{reason}")
    #resolved_state = cleanup_artifacts(resolved_state)
    #workflow_start_time = resolved_state[:workflow_start_time]
    #timestamp = CloudosBuildServer.Timex.Extensions.get_elapased_timestamp(workflow_start_time)
    #resolved_state = Map.merge(resolved_state, %{workflow_completed: true})
    #resolved_state = Map.merge(resolved_state, %{workflow_error: true})
    #resolved_state = Map.merge(resolved_state, %{workflow_duration: timestamp})
    #resolved_state = send_failure_notification(resolved_state, "Workflow has failed in #{timestamp}")
    flush_to_database(state)
    state
  end

  ## Workflow States
  def step_executed(event, from, state) do
  	IO.puts("finished executing the workflow step")
  	:gen_fsm.send_all_state_event(self(), :stop)
  end

  def workflow_completed(event, from, state) do
  	IO.puts("finished executing the workflow")
  	:gen_fsm.send_all_state_event(self(), :stop)
  end

  def resolve_deployment_repo(event, from, state) do
		IO.puts("resolve_deployment_repo")
		{:reply, :ok, :step_executed, state}
	end

	#def config(event, from, state) do
	#	IO.puts("config")
	#	{:reply, :ok, :step_executed, state}
	#end

	def build(event, from, state) do
    workflow_info = state[:workflow_info]

    {messaging_exchange_id, docker_build_machine} = DockerHostResolver.next_available
    if docker_build_machine == nil do
      {:reply, :ok, :step_executed, workflow_step_failed("Unable to request build - no build clusters are available!", state)}
    else
      payload = Map.merge(%{}, workflow_info)
      payload = Map.put(payload, :docker_build_host, docker_build_machine["primaryIP"])
      payload = Map.put(payload, :docker_build_host, docker_build_machine["primaryIP"])

      #default entries for all communications to children
      payload = Map.put(payload, :notifications_exchange_id, Configuration.get_current_exchange_id)
      payload = Map.put(payload, :notifications_broker_id, Configuration.get_current_broker_id)
      payload = Map.put(payload, :workflow_orchestration_exchange_id, Configuration.get_current_exchange_id)
      payload = Map.put(payload, :workflow_orchestrationnotifications_broker_id, Configuration.get_current_broker_id)      

      BuilderPublisher.build(state[:delivery_tag], messaging_exchange_id, payload)
    end

		{:reply, :ok, :step_executed, state}
	end

	def deploy(event, from, state) do
    workflow_info = state[:workflow_info]

    #default entries for all communications to children
    payload = Map.merge(%{}, workflow_info)
    payload = Map.put(payload, :notifications_exchange_id, Configuration.get_current_exchange_id)
    payload = Map.put(payload, :notifications_broker_id, Configuration.get_current_broker_id)
    payload = Map.put(payload, :workflow_orchestration_exchange_id, Configuration.get_current_exchange_id)
    payload = Map.put(payload, :workflow_orchestrationnotifications_broker_id, Configuration.get_current_broker_id)      

    BuilderPublisher.deploy(state[:delivery_tag], workflow_info[:etcd_token], payload)    

		{:reply, :ok, :step_executed, state}
	end

	def redeploy(event, from, state) do
		IO.puts("redeploy")
		{:reply, :ok, :step_executed, state}
	end

	def monitor_deployment(event, from, state) do
		IO.puts("monitor_deployment")
		{:reply, :ok, :step_executed, state}
	end

	def monitor_deployment(event, from, state) do
		IO.puts("monitor_deployment")
		{:reply, :ok, :step_executed, state}
	end
end
