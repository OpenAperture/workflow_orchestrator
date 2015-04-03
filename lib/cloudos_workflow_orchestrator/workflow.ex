#
# == workflow.ex
#
# This module contains the for interacting with a Workflow
#
require Logger
require Timex.Date

defmodule CloudOS.WorkflowOrchestrator.Workflow do
  use Timex

  @moduledoc """
  This module contains the for interacting with a Workflow
  """    

  alias CloudOS.WorkflowOrchestrator.Configuration
  alias CloudOS.WorkflowOrchestrator.Notifications.Publisher, as: NotificationsPublisher

  alias CloudOS.ManagerAPI
  alias CloudOS.ManagerAPI.EtcdCluster
  alias CloudOS.ManagerAPI.MessagingExchange
  alias CloudOS.ManagerAPI.Workflow, as: WorkflowAPI
  alias CloudOS.ManagerAPI.Response

  alias CloudOS.Timex.Extensions, as: TimexExtensions

  @doc """
  This module contains the logic for interacting with a CloudOS deployment repo.

  ## Options
   
  The `options` option defines the information needed to download and interact with a CloudOS deployment repo.
  The following values are accepted:
    * cloudos_repo - (required) String containing the repo org and name:  Perceptive-Cloud/myapp-deploy
    * cloudos_repo_branch - (optional) - String containing the commit/tag/branch to be used.  Defaults to 'master'

  ## Return values

  If the server is successfully created and initialized, the function returns
  `{:ok, pid}`, where pid is the pid of the server. If there already exists a
  process with the specified server name, the function returns
  `{:error, {:already_started, pid}}` with the pid of that process.

  If the `init/1` callback fails with `reason`, the function returns
  `{:error, reason}`. Otherwise, if it returns `{:stop, reason}`
  or `:ignore`, the process is terminated and the function returns
  `{:error, reason}` or `:ignore`, respectively.
  """
  @spec create_from_payload(Map) :: pid
  def create_from_payload(payload) do
    if (payload[:workflow_start_time] == nil) do
      payload = Map.merge(payload, %{workflow_start_time: Time.now()})
    end

    if (payload[:workflow_completed] == nil) do
      payload = Map.merge(payload, %{workflow_completed: false})
    end

    if (payload[:workflow_error] == nil) do
      resolved_state = Map.merge(payload, %{workflow_error: false})
    end

    if (payload[:event_log] == nil) do
      payload = Map.merge(payload, %{event_log: []})
    end

    raw_workflow_info = %{
    	workflow_id: payload[:workflow_id],
      deployment_repo: payload[:deployment_repo],
      deployment_repo_git_ref: payload[:deployment_repo_git_ref],
      source_repo: payload[:source_repo],
      source_repo_git_ref: payload[:source_repo_git_ref],
      source_commit_hash: payload[:source_commit_hash],
      milestones: Poison.encode!(payload[:milestones]),
      workflow_error: payload[:workflow_error],
      workflow_completed: payload[:workflow_completed],
      event_log: Poison.encode!(payload[:event_log]),
    }

    result = if (raw_workflow_info[:workflow_id] == nil || String.length(raw_workflow_info[:workflow_id]) == 0) do
	    case WorkflowAPI.create_workflow!(ManagerAPI.get_api, raw_workflow_info) do
	      nil -> {:error, "Failed to create a new Workflow with the ManagerAPI!"}
	      workflow_id -> {:ok, Map.put(raw_workflow_info, :workflow_id, workflow_id)}
	    end   
	  else
	  	{:ok, raw_workflow_info}
	  end

	  case result do
	  	{:ok, workflow_info} ->
		    case Agent.start_link(fn -> workflow_info end) do
		    	{:ok, pid} -> pid
		    	{:error, reason} -> {:error, "Failed to create Workflow Agent:  #{inspect reason}"}
		    end	
	  	{:error, reason} -> {:error, reason}
  	end
  end

  def get_id(workflow) do
  	get_info(workflow)[:workflow_id]
  end

  def get_info(workflow) do
  	Agent.get(workflow, fn info -> info end)
  end

  def complete?(workflow) do
  	get_info(workflow)[:workflow_completed]
  end

  def resolve_next_milestone(workflow) do
    workflow_info = get_info(workflow)

    current_step = workflow_info[:current_step]
    if current_step == nil do
    	resolved_workflow_info = send_success_notification(workflow_info, "Starting workflow...")
    else
      step_time = workflow_info[:step_time]
      timestamp = TimexExtensions.get_elapased_timestamp(step_time)
      if (step_time != nil) do
        resolved_workflow_info = Map.delete(workflow_info, :step_time)
      end

      workflow_step_durations = resolved_workflow_info[:workflow_step_durations]
      if (workflow_step_durations == nil) do
        workflow_step_durations = %{}
      end
      workflow_step_durations = Map.put(workflow_step_durations, to_string(current_step), timestamp)
      resolved_workflow_info = Map.put(resolved_workflow_info, :workflow_step_durations, workflow_step_durations)

      resolved_workflow_info = send_success_notification(resolved_workflow_info, "Completed Workflow Milestone:  #{inspect current_step}, in #{timestamp}")
    end

    next_workflow_step = resolve_next_step(resolved_workflow_info)
    if next_workflow_step == nil do
      resolved_workflow_info = Map.put(resolved_workflow_info, :workflow_completed, true)

      timestamp = TimexExtensions.get_elapased_timestamp(resolved_workflow_info[:workflow_start_time])
      resolved_workflow_info = Map.put(resolved_workflow_info, :workflow_duration, timestamp)
      resolved_workflow_info = send_success_notification(resolved_workflow_info, "Workflow completed in #{timestamp}")

      next_workflow_step = :workflow_completed
    else
      resolved_workflow_info = Map.merge(resolved_workflow_info, %{step_time: Time.now()})
      resolved_workflow_info = send_success_notification(resolved_workflow_info, "Starting Workflow Milestone:  #{inspect next_workflow_step}")
    end
    resolved_workflow_info = Map.put(resolved_workflow_info, :current_step, next_workflow_step)

    Agent.update(workflow, fn _ -> resolved_workflow_info end)
    save(workflow)

    next_workflow_step
  end

	def send_success_notification(workflow_info, message) do
		send_notification(workflow_info, true, message)
	end

	def send_failure_notification(workflow_info, message) do
		send_notification(workflow_info, false, message)
	end

	def send_notification(workflow_info, is_success, message) do
		prefix = "[CloudOS Workflow][#{workflow_info[:workflow_id]}]"
    Logger.debug("#{prefix} #{message}")
    workflow_info = add_event_to_log(workflow_info, message, prefix)
    NotificationsPublisher.hipchat_notification(is_success, prefix, message)
	end

  @doc """
  Method to add an event to the workflow's event log

  ## Options

  The `state` option represents the server's current state

  The `event` option defines a String containing the event to track

  The `prefix` option defines an optional String prefix for the event

  ## Return Values

  The updated server state
  """
  @spec add_event_to_log(Map, String.t(), String.t()) :: Map
  def add_event_to_log(workflow_info, event, prefix \\ nil) do
    if (prefix == nil) do
      prefix = "[CloudOS Workflow][#{workflow_info[:workflow_id]}]"
    end

    event_log = workflow_info[:event_log]
    if (event_log == nil) do
      event_log = []
    end
    event_log = event_log ++ ["#{prefix} #{event}"]
    Map.put(workflow_info, :event_log, event_log)
  end

	def save(workflow) do
		workflow_info = get_info(workflow)

    workflow_payload = %{
      id: workflow_info[:workflow_id],
      deployment_repo: workflow_info[:deployment_repo],
      deployment_repo_git_ref: workflow_info[:deployment_repo_git_ref],
      source_repo: workflow_info[:source_repo],
      source_repo_git_ref: workflow_info[:source_repo_git_ref],
      source_commit_hash: workflow_info[:source_commit_hash],
      milestones: Poison.encode!(workflow_info[:milestones]),
      current_step: "#{workflow_info[:current_step]}",
      elapsed_step_time: TimexExtensions.get_elapased_timestamp(workflow_info[:step_time]),
      elapsed_workflow_time: TimexExtensions.get_elapased_timestamp(workflow_info[:workflow_start_time]),
      workflow_duration: workflow_info[:workflow_duration],
      workflow_step_durations: Poison.encode!(workflow_info[:workflow_step_durations]),
      workflow_error: workflow_info[:workflow_error],
      workflow_completed: workflow_info[:workflow_completed],
      event_log: Poison.encode!(workflow_info[:event_log]),
    }
		
    case WorkflowAPI.update_workflow(ManagerAPI.get_api, workflow_info[:workflow_id], workflow_payload) do
      %Response{status: 204} -> :ok
      %Response{status: status} -> 
        error_message = "Failed to save workflow; server returned #{status}"
        Logger.error(error_message)
        {:error, error_message}
		end
  end	

  @doc """
  Method to determine the next workflow step, based on the current state of the workflow

  ## Options

  The `state` option is the current state (GenServer) of the workflow

  ## Return Values

  The atom containing the next available state or nil
  """
  @spec resolve_next_step(term) :: term
  def resolve_next_step(workflow_info) do
    if workflow_info[:workflow_steps] == nil || length(workflow_info[:workflow_steps]) == 0 do
      nil
    else
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
  end  

  def workflow_failed(workflow, reason) do
  	workflow_info = get_info(workflow)
    workflow_info = send_failure_notification(workflow, "Workflow Milestone Failed:  #{inspect workflow_info[:current_step]}.  Reason:  #{reason}")
    workflow_info = Map.merge(workflow_info, %{workflow_completed: true})
    workflow_info = Map.merge(workflow_info, %{workflow_error: true})

    timestamp = TimexExtensions.get_elapased_timestamp(workflow_info[:workflow_start_time])
    workflow_info = Map.merge(workflow_info, %{workflow_duration: timestamp})
    workflow_info = send_failure_notification(workflow_info, "Workflow has failed in #{timestamp}")

    Agent.update(workflow, fn _ -> workflow_info end)
    save(workflow)
  end
end