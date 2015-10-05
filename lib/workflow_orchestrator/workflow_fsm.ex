#
# == workflow_fsm.ex
#
# This module contains the gen_fsm for Workflow Orchestration.  Most executions
# through this FSM will follow one of the following path(s):
#
#   * Workflow is complete
#     :workflow_starting
#     :workflow_completed
#   * Build
#     :workflow_starting
#     :build
#     :workflow_completed
#   * Deploy
#     :workflow_starting
#     :deploy
#     :workflow_completed
#
require Logger
require Timex.Date

defmodule OpenAperture.WorkflowOrchestrator.WorkflowFSM do

  @moduledoc """
  This module contains the gen_fsm for Workflow Orchestration
  """

  use Timex

  @behaviour :gen_fsm

  alias OpenAperture.WorkflowOrchestrator.Workflow
  alias OpenAperture.WorkflowOrchestrator.Configuration
  alias OpenAperture.WorkflowOrchestrator.Dispatcher
  alias OpenAperture.WorkflowOrchestrator.Builder.DockerHostResolver
  alias OpenAperture.WorkflowOrchestrator.Builder.Publisher, as: BuilderPublisher
  alias OpenAperture.WorkflowOrchestrator.Deployer.Publisher, as: DeployerPublisher
  alias OpenAperture.WorkflowOrchestrator.Deployer.EtcdClusterMessagingResolver

  alias OpenAperture.WorkflowOrchestratorApi.Request, as: OrchestratorRequest
  alias OpenAperture.WorkflowOrchestratorApi.WorkflowOrchestrator.Publisher, as: WorkflowOrchestratorPublisher

  @doc """
  Method to start a WorkflowFSM

  ## Options

  The `payload` options defines the payload of the Workflow

  The `delivery_tag` options defines the identifier of the request message to which this FSM is associated

  ## Return Values

  {:ok, WorkflowFSM} | {:error, reason}
  """
  @spec start_link(map, String.t) :: {:ok, pid} | {:error, String.t}
	def start_link(payload, delivery_tag) do
    case Workflow.create_from_payload(payload) do
      {:error, reason} -> {:error, reason}
      workflow -> :gen_fsm.start_link(__MODULE__, %{workflow: workflow, delivery_tag: delivery_tag}, [])
    end
	end

  @doc """
  Method to execute a (rescursive) run of the WorkflowFSM

  ## Options

  The `workflowfsm` option defines the PID of the FSM

  ## Return Values

  :completed
  """
  @spec execute(pid) :: :completed
  def execute(workflowfsm) do
    case :gen_fsm.sync_send_event(workflowfsm, :execute_next_workflow_step, 15000) do
      :in_progress -> execute(workflowfsm)
      {result, workflow} -> {result, workflow}
    end
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:init-1

  ## Options

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:ok, :workflow_starting, state_data}
  """
  @spec init(pid) :: {:ok, :workflow_starting, map}
	def init(state_data) do
    state_data = Map.put(state_data, :workflow_fsm_id, "#{UUID.uuid1()}")
    state_data = Map.put(state_data, :workflow_fsm_prefix, "[WorkflowFSM][#{state_data[:workflow_fsm_id]}][Workflow][#{Workflow.get_id(state_data[:workflow])}]")
    {:ok, :workflow_starting, state_data}
	end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:terminate-3

  ## Options

  The `reason` option defines the termination reason (:shutdown, :normal)

  The `current_state` option contains the last state of the :gen_fsm server

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

  :ok
  """
  @spec terminate(term, term, map) :: :ok
	def terminate(_reason, _current_state, state_data) do
		Logger.debug("#{state_data[:workflow_fsm_prefix]} Workflow Orchestration has finished normally")
		:ok
	end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:code_change-4

  ## Options

  The `old_vsn` option:  OldVsn = Vsn | {down, Vsn}

  The `current_state` option contains the last state of the :gen_fsm server

  The `state_data` option contains the default state data of the :gen_fsm server

  The `opts` option contains additional extra options

  ## Return Values

      {:ok, term, map}
  """
  @spec code_change(term, term, map, term) :: {:ok, term, map}
  def code_change(_old_vsn, current_state, state_data, _opts) do
    {:ok, current_state, state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:handle_info-3

  ## Options

  The `info` option contains additional extra options

  The `current_state` option contains the last state of the :gen_fsm server

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:next_state, term, map}
  """
  @spec handle_info(term, term, map) :: {:next_state,term, map}
  def handle_info(_info, current_state, state_data) do
    {:next_state,current_state,state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:handle_event-3

  ## Options

  The `event` option contains the current event received by the server

  The `current_state` option contains the last state of the :gen_fsm server

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:next_state, term, map}
  """
  @spec handle_event(term, term, map) :: {:next_state,term, map}
  def handle_event(_event, current_state, state_data) do
    {:next_state,current_state,state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:handle_sync_event-4

  ## Options

  The `event` option contains the current event received by the server

  The `from` option contains the caller of the server

  The `current_state` option contains the last state of the :gen_fsm server

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:next_state, term, map}
  """
  @spec handle_sync_event(term, term, term, map) :: {:next_state,term, map}
  def handle_sync_event(_event, _from, current_state, state_data) do
    {:next_state,current_state,state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :workflow_starting
  This callback will take the following action(s):
    * Save the current Workflow
    * If workflow is not completed, transition to the next workflow state
    * If workflow is completed, transition to :workflow_completed

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:reply, :in_progress, next_milestone, state_data}
  """
  @spec workflow_starting(term, term, map) :: {:reply, :in_progress, term, map}
  def workflow_starting(_current_state, _from, state_data) do
    Logger.debug("#{state_data[:workflow_fsm_prefix]} Starting Workflow Orchestration for request message #{state_data[:delivery_tag]}...")

    Logger.debug("#{state_data[:workflow_fsm_prefix]} Saving workflow...")
    Workflow.save(state_data[:workflow])

    case Workflow.complete?(state_data[:workflow]) do
      true ->
        if Workflow.failed?(state_data[:workflow]) do
          Workflow.workflow_failed(state_data[:workflow], "Milestone worker has reported a failure")
        else
          Logger.debug("#{state_data[:workflow_fsm_prefix]} Workflow is complete")
        end

        {:reply, :in_progress, :workflow_completed, state_data}
      false ->
        Logger.debug("#{state_data[:workflow_fsm_prefix]} Workflow has not finished, resolving next milestone...")
        {:reply, :in_progress, Workflow.resolve_next_milestone(state_data[:workflow]), state_data}
    end
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :workflow_completed
  This callback will take the following action(s):
    * Stop the :gen_fsm

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

  {:stop, :normal, {:completed, state_data[:workflow]}, state_data}
  """
  @spec workflow_completed(term, term, map) :: {:stop, :normal, {:completed, pid}, map}
  def workflow_completed(_current_state, _from, state_data) do
    Logger.debug("#{state_data[:workflow_fsm_prefix]} Finishing Workflow Orchestration...")

    if Workflow.complete?(state_data[:workflow]) do
      Workflow.send_workflow_completed_email(state_data[:workflow])
    end

    Dispatcher.acknowledge(state_data[:delivery_tag])
    {:stop, :normal, {:completed, state_data[:workflow]}, state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :build
  This callback will take the following action(s):
    * Resolve a messaging_exchange to send a Builder message
      * Fail the workflow if the resolution fails
    * Publish a Builder request
    * Transition to :workflow_completed

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:reply, :in_progress, :workflow_completed, state_data}
  """
  @spec build(term, term, map) :: {:reply, :in_progress, :workflow_completed, map}
  def build(_event, _from, state_data) do
    call_builder(state_data)
  end

  @spec config(term, term, map) :: {:reply, :in_progress, :workflow_completed, map}
  def config(_event, _from, state_data) do
    call_builder(state_data)
  end

  def call_builder(state_data) do
    type = Workflow.get_info(state_data[:workflow])[:current_step]
    Logger.debug("#{state_data[:workflow_fsm_prefix]} Requesting #{type}...")
    {messaging_exchange_id, docker_build_etcd_cluster} = DockerHostResolver.next_available

    workflow_info = Workflow.get_info(state_data[:workflow])
    if workflow_info[:build_messaging_exchange_id] != nil do
      messaging_exchange_id = workflow_info[:build_messaging_exchange_id]
      Workflow.add_success_notification(state_data[:workflow], "The Workflow request has overriden the default build messaging_exchange_id to #{messaging_exchange_id}")
    end
    cond do
      docker_build_etcd_cluster == nil ->
        Workflow.workflow_failed(state_data[:workflow], "Unable to request #{type} - no build clusters are available!")
      !OpenAperture.ManagerApi.MessagingExchange.exchange_has_modules_of_type?(messaging_exchange_id, "builder") ->
        Workflow.workflow_failed(state_data[:workflow], "Unable to request #{type} - no Builders are currently accessible in exchange #{messaging_exchange_id}!")
      true ->
        Workflow.add_success_notification(state_data[:workflow], "Dispatching a #{type} request to exchange #{messaging_exchange_id}, docker build cluster #{docker_build_etcd_cluster["etcd_token"]}...")

        request = OrchestratorRequest.from_payload(Workflow.get_info(state_data[:workflow]))
        request = %{request | docker_build_etcd_token: docker_build_etcd_cluster["etcd_token"]}
        request = %{request | notifications_exchange_id: Configuration.get_current_exchange_id}
        request = %{request | notifications_broker_id: Configuration.get_current_broker_id}
        request = %{request | workflow_orchestration_exchange_id: Configuration.get_current_exchange_id}
        request = %{request | workflow_orchestration_broker_id: Configuration.get_current_broker_id}
        request = %{request | orchestration_queue_name: "workflow_orchestration"}

        Logger.debug("#{state_data[:workflow_fsm_prefix]} Saving workflow...")
        Workflow.save(state_data[:workflow])

        BuilderPublisher.build(state_data[:delivery_tag], messaging_exchange_id, OrchestratorRequest.to_payload(request))
    end

    # after this action, we want to complete the current Workflow Orchestration.  The worker will
    # call back in after it's action has been completed
    {:reply, :in_progress, :workflow_completed, state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :deploy
  This callback will take the following action(s):
    * Resolve a messaging_exchange to send a Deployer message
      * Fail the workflow if the resolution fails
    * Publish a Deployer request
    * Transition to :workflow_completed

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:reply, :in_progress, :workflow_completed, state_data}
  """
  @spec deploy(term, term, map) :: {:reply, :in_progress, :workflow_completed, map}
  def deploy(_event, _from, state_data) do
    call_deployer(state_data)
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :deploy_oa
  This callback will take the following action(s):
    * Resolve a messaging_exchange to send a Deployer message
      * Fail the workflow if the resolution fails
    * Publish a Deployer request
    * Transition to :workflow_completed

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:reply, :in_progress, :workflow_completed, state_data}
  """
  @spec deploy_oa(term, term, map) :: {:reply, :in_progress, :workflow_completed, map}
  def deploy_oa(_event, _from, state_data) do
    call_deployer(state_data)
  end

  @spec call_deployer(map) :: {:reply, :in_progress, :workflow_completed, map}
  defp call_deployer(state_data) do
    type = Workflow.get_info(state_data[:workflow])[:current_step]
    Logger.debug("#{state_data[:workflow_fsm_prefix]} Requesting #{inspect type}...")

    workflow_info = Workflow.get_info(state_data[:workflow])
    if workflow_info[:etcd_token] == nil || String.length(workflow_info[:etcd_token]) == 0 do
      Workflow.workflow_failed(state_data[:workflow], "Unable to execute deployment - an invalid deployment cluster was provided!")
    else
      if workflow_info[:deploy_messaging_exchange_id] != nil do
        messaging_exchange_id = workflow_info[:deploy_messaging_exchange_id]
        Workflow.add_success_notification(state_data[:workflow], "The Workflow request has overriden the default deploy messaging_exchange_id to #{messaging_exchange_id}")
      else
        messaging_exchange_id = EtcdClusterMessagingResolver.exchange_for_cluster(workflow_info[:etcd_token])
      end

      cond do
        messaging_exchange_id == nil ->
          Workflow.workflow_failed(state_data[:workflow], "Unable to request deploy to cluster #{workflow_info[:etcd_token]} - cluster is not associated with an exchange!")
        !OpenAperture.ManagerApi.MessagingExchange.exchange_has_modules_of_type?(messaging_exchange_id, "deployer") ->
          Workflow.workflow_failed(state_data[:workflow], "Unable to request deploy - no deploy clusters are available in exchange #{messaging_exchange_id}!")
        true ->
          Workflow.add_success_notification(state_data[:workflow], "Dispatching a deploy request to exchange #{messaging_exchange_id}, deployment cluster #{workflow_info[:etcd_token]}...")

          #default entries for all communications to children
          request = OrchestratorRequest.from_payload(Workflow.get_info(state_data[:workflow]))
          request = %{request | notifications_exchange_id: Configuration.get_current_exchange_id}
          request = %{request | notifications_broker_id: Configuration.get_current_broker_id}
          request = %{request | workflow_orchestration_exchange_id: Configuration.get_current_exchange_id}
          request = %{request | workflow_orchestration_broker_id: Configuration.get_current_broker_id}
          request = %{request | orchestration_queue_name: "workflow_orchestration"}

          Logger.debug("#{state_data[:workflow_fsm_prefix]} Saving workflow...")
          Workflow.save(state_data[:workflow])

          if type == :deploy do
            DeployerPublisher.deploy(state_data[:delivery_tag], messaging_exchange_id, OrchestratorRequest.to_payload(request))
          else
            DeployerPublisher.deploy_oa(state_data[:delivery_tag], messaging_exchange_id, OrchestratorRequest.to_payload(request))
          end
      end
    end

    # after this action, we want to complete the current Workflow Orchestration.  The worker will
    # call back in after it's action has been completed
    {:reply, :in_progress, :workflow_completed, state_data}
  end

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :deploy
  This callback will take the following action(s):
    * Publish a Deployer request to a Deployer in the same exchange
    * Transition to :workflow_completed

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:reply, :in_progress, :workflow_completed, state_data}
  """
  @spec deploy_ecs(term, term, map) :: {:reply, :in_progress, :workflow_completed, map}
  def deploy_ecs(_event, _from, state_data) do
    Logger.debug("#{state_data[:workflow_fsm_prefix]} Requesting #{inspect Workflow.get_info(state_data[:workflow])[:current_step]}...")

    unless OpenAperture.ManagerApi.MessagingExchange.exchange_has_modules_of_type?(Configuration.get_current_exchange_id, "deployer") do
      Workflow.workflow_failed(state_data[:workflow], "Unable to request deploy to ECS - no deploy clusters are available in exchange #{Configuration.get_current_exchange_id}!")
    else
      #default entries for all communications to children
      request = OrchestratorRequest.from_payload(Workflow.get_info(state_data[:workflow]))
      request = %{request | notifications_exchange_id: Configuration.get_current_exchange_id}
      request = %{request | notifications_broker_id: Configuration.get_current_broker_id}
      request = %{request | workflow_orchestration_exchange_id: Configuration.get_current_exchange_id}
      request = %{request | workflow_orchestration_broker_id: Configuration.get_current_broker_id}
      request = %{request | orchestration_queue_name: "workflow_orchestration"}

      Logger.debug("#{state_data[:workflow_fsm_prefix]} Saving workflow...")
      Workflow.save(state_data[:workflow])

      Workflow.add_success_notification(state_data[:workflow], "Dispatching an ECS deploy request to exchange #{Configuration.get_current_exchange_id}...")
      DeployerPublisher.deploy(state_data[:delivery_tag], Configuration.get_current_exchange_id, OrchestratorRequest.to_payload(request))
    end

    {:reply, :in_progress, :workflow_completed, state_data}
  end  

  @doc """
  :gen_fsm callback - http://www.erlang.org/doc/man/gen_fsm.html#Module:StateName-3 for the state :scheduled
  This callback will take the following action(s):
    * Determine the correct amount of time before the request should be re-evaluated
    * Sleep for a period of time (not necessarily the full duration, as we'll want to evaluate for terminated workflows)
    * Refresh the Workflow
    * Requeue a message

  ## Options

  The `current_state` option contains the last state of the :gen_fsm server

  The `from` option contains the caller of the state transition

  The `state_data` option contains the default state data of the :gen_fsm server

  ## Return Values

      {:reply, :in_progress, :workflow_completed, state_data}
  """
  @spec scheduled(term, term, map) :: {:reply, :in_progress, :workflow_completed, map}
  def scheduled(_event, _from, state_data) do
    workflow_info = Workflow.get_info(state_data[:workflow])
    if workflow_info[:scheduled_start_time] == nil do
      Workflow.workflow_failed(state_data[:workflow], "Unable to execute deployment - the scheduled milestone was invoked, but no scheduled_start_time was set!")
    else
      sleep_delay_factor = Application.get_env(:openaperture_workflow_orchestrator, :sleep_delay_factor, 1)

      datetime = DateFormat.parse!(workflow_info[:scheduled_start_time], "{RFC1123}")
      erl_date = DateConvert.to_erlang_datetime(datetime)
      scheduled_start_time_seconds = :calendar.datetime_to_gregorian_seconds(erl_date)
      now_seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time())
      remaining_seconds = scheduled_start_time_seconds - now_seconds
      cond do
        # sleep for a max of an hour
        remaining_seconds > 3600 ->
          Workflow.add_success_notification(state_data[:workflow], "Workflow is not scheduled to start until #{workflow_info[:scheduled_start_time]} (#{remaining_seconds} seconds remain).  Next evaluation will occur in 1 hour")
          Workflow.save(state_data[:workflow])
          :timer.sleep(3600000 * sleep_delay_factor)
          #wipe out the current step and queue another evaluation
          Workflow.refresh(state_data[:workflow])
          workflow_info = Workflow.get_info(state_data[:workflow])
          workflow_info = Map.put(workflow_info, :current_step, nil)
          request = OrchestratorRequest.from_payload(workflow_info)
          WorkflowOrchestratorPublisher.execute_orchestration(request)
        remaining_seconds > 0 ->
          Workflow.add_success_notification(state_data[:workflow], "Workflow is not scheduled to start until #{workflow_info[:scheduled_start_time]} (#{remaining_seconds} seconds remain).  Next evaluation will occur in #{remaining_seconds} seconds")
          Workflow.save(state_data[:workflow])
          :timer.sleep((remaining_seconds+10) * 1000 * sleep_delay_factor)
          #wipe out the current step and queue another evaluation
          Workflow.refresh(state_data[:workflow])
          workflow_info = Workflow.get_info(state_data[:workflow])
          workflow_info = Map.put(workflow_info, :current_step, nil)
          request = OrchestratorRequest.from_payload(workflow_info)
          WorkflowOrchestratorPublisher.execute_orchestration(request)          
        true ->
          #complete the milestone
          Workflow.add_success_notification(state_data[:workflow], "Workflow is now scheduled to start")
          Workflow.save(state_data[:workflow])
          WorkflowOrchestratorPublisher.execute_orchestration(OrchestratorRequest.from_payload(Workflow.get_info(state_data[:workflow])))
      end
    end

    # after this action, we want to complete the current Workflow Orchestration.  The worker will
    # call back in after it's action has been completed
    {:reply, :in_progress, :workflow_completed, state_data}
  end
end
