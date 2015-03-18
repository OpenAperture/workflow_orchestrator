defmodule CloudOS.WorkflowOrchestrator.Workflow do

	def start_link(workflow_info, additional_options) do
		resolved_state = Map.merge(workflow_info, additional_options)
		:gen_fsm.start_link(__MODULE__, resolved_state, [])
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
		current_step = state[:current_step]
    if current_step == nil do
      resolved_state = send_success_notification(state, "Starting workflow...")
    else
      step_time = state[:step_time]
      timestamp = CloudosBuildServer.Timex.Extensions.get_elapased_timestamp(step_time)
      if (step_time != nil) do
        resolved_state = Map.delete(state, :step_time)
      end

      workflow_step_durations = resolved_state[:workflow_step_durations]
      if (workflow_step_durations != nil) do
        resolved_state = Map.delete(resolved_state, :workflow_step_durations)
      else
        workflow_step_durations = %{}
      end
      workflow_step_durations = Map.put(workflow_step_durations, "#{inspect current_step}", timestamp)
      resolved_state = Map.merge(resolved_state, %{workflow_step_durations: workflow_step_durations})

      resolved_state = send_success_notification(resolved_state, "Completed Workflow Milestone:  #{inspect current_step}, in #{timestamp}")
    end

    resolved_state = Map.merge(resolved_state, %{step_time: Time.now()})
    flush_to_database(resolved_state)

    next_workflow_step = resolve_next_step(resolved_state)
    if next_workflow_step == nil do
    	next_workflow_step = :workflow_completed
    end
    #execute_workflow_step(resolve_next_step(resolved_state), resolved_state)

		#{:reply, reply, new state, new state data}
		{:reply, :ok, next_workflow_step, resolved_state}
	end

	def send_success_notification(state, message) do
		#TODO:  placeholder
		state
	end

	def send_failure_notification(state, message) do
		#TODO:  placeholder
		state		
	end

	defp send_notification(state, message) do

		prefix = "[CloudOS Build Server][CloudOS Workflow][#{state[:workflow_id]}]"
    Logger.error("#{prefix} #{message}")
    resolved_state = add_event_to_log(state, message, prefix)
    WorkflowNotification.send_notification(resolved_state[:notification_server], prefix, message, false)
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
  	current_step = state[:current_step]
  	{_, next_step} = Enum.reduce state[:workflow_steps], {false, nil}, fn(available_step, {use_next_step, next_step})->
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

  ## Workflow States
  def step_executed(event, from, state) do
  	IO.puts("finished executing the workflow step")
  	gen_fsm:send_all_state_event(self(), :stop)
  end

  def workflow_completed(event, from, state) do
  	IO.puts("finished executing the workflow")
  	gen_fsm:send_all_state_event(self(), :stop)
  end

  def resolve_deployment_repo(event, from, state) do
		IO.puts("resolve_deployment_repo")
		{:reply, :ok, :step_executed, state}
	end

	def config(event, from, state) do
		IO.puts("config")
		{:reply, :ok, :step_executed, state}
	end

	def build(event, from, state) do
		IO.puts("build")
		{:reply, :ok, :step_executed, state}
	end

	def deploy(event, from, state) do
		IO.puts("deploy")
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
