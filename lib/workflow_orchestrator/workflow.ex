#
# == workflow.ex
#
# This module contains the for interacting with a Workflow
#
require Logger
require Timex.Date

defmodule OpenAperture.WorkflowOrchestrator.Workflow do
  use Timex

  @moduledoc """
  This module contains the for interacting with a Workflow
  """    

  alias OpenAperture.WorkflowOrchestrator.Notifications.Publisher, as: NotificationsPublisher

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.Workflow, as: WorkflowAPI
  alias OpenAperture.ManagerApi.Response

  alias OpenAperture.Timex.Extensions, as: TimexExtensions

  @doc """
  This module contains the for interacting with a Workflow
  """

  @doc """
  Method to create a Workflow

  ## Options
   
  The `payload` option defines the Workflow info that should be stored and referenced

  ## Return values

  pid (Workflow) | {:error, reason}
  """
  @spec create_from_payload(Map) :: pid | {:error, String.t()}
  def create_from_payload(payload) do
    defaults = %{
      workflow_start_time: Time.now(),
      workflow_completed: false,
      workflow_error: false,
      event_log: []
    }

    #the payload may override the defaults back to nil
    workflow_info = Map.merge(defaults, payload)
    if workflow_info[:workflow_start_time] == nil do
      workflow_start_time = Map.put(workflow_info, :workflow_start_time, Time.now())
    end
    
    if workflow_info[:workflow_completed] == nil do
      workflow_start_time = Map.put(workflow_info, :workflow_completed, false)
    end

    if workflow_info[:workflow_error] == nil do
      workflow_start_time = Map.put(workflow_info, :workflow_error, false)
    end

    if workflow_info[:event_log] == nil do
      workflow_start_time = Map.put(workflow_info, :event_log, [])
    end

    Logger.debug("create_from_payload - workflow_start_time:  #{inspect workflow_info[:workflow_start_time]}")
    case Agent.start_link(fn -> workflow_info end) do
    	{:ok, pid} -> pid
    	{:error, reason} -> {:error, "Failed to create Workflow Agent:  #{inspect reason}"}
    end	
  end

  @doc """
  Method to retrieve the id from a workflow

  ## Options
   
  The `workflow` option defines the Workflow referenced

  ## Return values

  identifier
  """
  @spec get_id(pid) :: String.t()
  def get_id(workflow) do
  	get_info(workflow)[:id]
  end

  @doc """
  Method to retrieve the info associated with a workflow

  ## Options
   
  The `workflow` option defines the Workflow referenced

  ## Return values

  Map
  """
  @spec get_info(pid) :: Map
  def get_info(workflow) do
  	Agent.get(workflow, fn info -> info end)
  end

  @doc """
  Method to determine if a Workflow is completed

  ## Options
   
  The `workflow` option defines the Workflow referenced

  ## Return values

  boolean
  """
  @spec complete?(pid) :: term
  def complete?(workflow) do
  	completed = get_info(workflow)[:workflow_completed]
    if completed != nil do
      completed
    else
      false
    end
  end

  @doc """
  Method to determine if a Workflow has completed in error

  ## Options
   
  The `workflow` option defines the Workflow referenced

  ## Return values

  boolean
  """
  @spec failed?(pid) :: term
  def failed?(workflow) do
    failed = get_info(workflow)[:workflow_error]
    if failed != nil do
      failed
    else
      false
    end
  end

  @doc """
  Method to resolve the next Workflow step

  ## Options
   
  The `workflow` option defines the Workflow referenced

  ## Return values

  atom with next step
  """
  @spec resolve_next_milestone(pid) :: term
  def resolve_next_milestone(workflow) do
    workflow_info = get_info(workflow)

    current_step = workflow_info[:current_step]
    Logger.debug("Resolving next milestone for Workflow #{workflow_info[:id]}, current step is #{inspect current_step}")

    if current_step == nil do
    	resolved_workflow_info = send_success_notification(workflow_info, "Starting workflow...")
    else
      resolved_workflow_info = workflow_info

      step_time = resolved_workflow_info[:step_time]
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

    Logger.debug("Resolving next milestone for Workflow #{workflow_info[:id]}, next step is #{inspect next_workflow_step}")
    next_workflow_step
  end

  @doc """
  Method to publish a "success" notification

  ## Options
   
  The `workflow_info` option defines the Workflow info Map

  The `message` option defines the message to publish

  ## Return values

  Map, containing the updated workflow_info
  """
  @spec send_success_notification(Map, String.t()) :: Map
	def send_success_notification(workflow_info, message) do
		send_notification(workflow_info, true, message)
	end

  @doc """
  Method to publish a "failure" notification

  ## Options
   
  The `workflow_info` option defines the Workflow info Map

  The `message` option defines the message to publish

  ## Return values

  Map, containing the updated workflow_info
  """
  @spec send_failure_notification(Map, String.t()) :: Map
	def send_failure_notification(workflow_info, message) do
		send_notification(workflow_info, false, message)
	end

  @doc """
  Method to publish a notification

  ## Options
   
  The `workflow_info` option defines the Workflow info Map

  The `is_success` option defines failure/success of the message

  The `message` option defines the message to publish

  ## Return values

  Map, containing the updated workflow_info
  """
  @spec send_notification(Map, term, String.t()) :: Map
	def send_notification(workflow_info, is_success, message) do
		prefix = "[OpenAperture Workflow][#{workflow_info[:id]}]"
    Logger.debug("#{prefix} #{message}")
    workflow_info = add_event_to_log(workflow_info, message, prefix)
    NotificationsPublisher.hipchat_notification(is_success, prefix, message)

    workflow_info
	end

  @doc """
  Method to add an event to the workflow's event log

  ## Options

  The `workflow_info` option defines the Workflow info Map

  The `event` option defines a String containing the event to track

  The `prefix` option defines an optional String prefix for the event

  ## Return Values

  The updated Workflow info
  """
  @spec add_event_to_log(Map, String.t(), String.t()) :: Map
  def add_event_to_log(workflow_info, event, prefix \\ nil) do
    if (prefix == nil) do
      prefix = "[OpenAperture Workflow][#{workflow_info[:id]}]"
    end

    event_log = workflow_info[:event_log]
    if (event_log == nil) do
      event_log = []
    end
    event_log = event_log ++ ["#{prefix} #{event}"]
    Map.put(workflow_info, :event_log, event_log)
  end

  @doc """
  Method to save Workflow info to the database

  ## Options

  The `workflow` option defines the Workflow referenced

  ## Return Value

  :ok | {:error, reason}
  """
  @spec save(pid) :: :ok | {:error, String.t()}
	def save(workflow) do
		workflow_info = get_info(workflow)

    workflow_error = workflow_info[:workflow_error]
    if workflow_error == nil && workflow_info[:workflow_completed] != nil  do
      workflow_error = false
    end

    workflow_payload = %{
      id: workflow_info[:id],
      deployment_repo: workflow_info[:deployment_repo],
      deployment_repo_git_ref: workflow_info[:deployment_repo_git_ref],
      source_repo: workflow_info[:source_repo],
      source_repo_git_ref: workflow_info[:source_repo_git_ref],
      source_commit_hash: workflow_info[:source_commit_hash],
      milestones: workflow_info[:milestones],
      current_step: "#{workflow_info[:current_step]}",
      elapsed_step_time: TimexExtensions.get_elapased_timestamp(workflow_info[:step_time]),
      elapsed_workflow_time: TimexExtensions.get_elapased_timestamp(workflow_info[:workflow_start_time]),
      workflow_duration: workflow_info[:workflow_duration],
      workflow_step_durations: workflow_info[:workflow_step_durations],
      workflow_error: workflow_error,
      workflow_completed: workflow_info[:workflow_completed],
      event_log: workflow_info[:event_log],
    }
		
    case WorkflowAPI.update_workflow(ManagerApi.get_api, workflow_info[:id], workflow_payload) do
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

  The `workflow_info` option defines the Workflow info Map

  ## Return Values

  The atom containing the next available state or nil
  """
  @spec resolve_next_step(Map) :: term
  def resolve_next_step(workflow_info) do
    if workflow_info[:milestones] == nil || length(workflow_info[:milestones]) == 0 do
      nil
    else
    	current_step = workflow_info[:current_step]
      current_step_atom = if current_step == nil || is_atom(current_step) do
        current_step
      else
        String.to_atom(current_step)
      end
      
    	{_, next_step} = Enum.reduce workflow_info[:milestones], {false, nil}, fn(available_step, {use_next_step, next_step})->
        available_step_atom = if available_step == nil || is_atom(available_step) do
          available_step
        else
          String.to_atom(available_step)
        end

    		#we already found the next step
    		if (next_step != nil) do
    			{false, next_step}
    		else
    			#we're just starting the workflow
  				if (current_step_atom == nil) do
    				{false, available_step_atom}
    			else
    				if (use_next_step) do
    					{false, available_step_atom}
    				else
  	  				#the current item in the list is the current workflow step
  	  				if (current_step_atom == available_step_atom) do
  	  					{true, next_step}
  	  				else
  	  					#the current item in the list is NOT the current workflow step
  	  					{false, next_step}
  	  				end
  	  			end
    			end
    		end
    	end
      if next_step == nil || is_atom(next_step) do
        next_step
      else
        String.to_atom(next_step)
      end
    end
  end  

  @doc """
  Method to complete a Workflow in failure

  ## Options

  The `workflow` option defines the Workflow referenced

  The `reason` option defines the String reason for the failure

  ## Return Values

  :ok | {:error, reason}
  """
  @spec workflow_failed(pid, String.t()) :: :ok | {:error, String.t()}
  def workflow_failed(workflow, reason) do
  	workflow_info = get_info(workflow)
    workflow_info = send_failure_notification(workflow_info, "Workflow Milestone Failed:  #{inspect workflow_info[:current_step]}.  Reason:  #{reason}")
    workflow_info = Map.merge(workflow_info, %{workflow_completed: true})
    workflow_info = Map.merge(workflow_info, %{workflow_error: true})

    Logger.debug("workflow_failed - workflow_start_time:  #{inspect workflow_info[:workflow_start_time]}")
    timestamp = TimexExtensions.get_elapased_timestamp(workflow_info[:workflow_start_time])
    workflow_info = Map.merge(workflow_info, %{workflow_duration: timestamp})
    workflow_info = send_failure_notification(workflow_info, "Workflow has failed in #{timestamp}")

    workflow_step_durations = workflow_info[:workflow_step_durations]
    if (workflow_step_durations == nil) do
      workflow_step_durations = %{}
    end

    timestamp = TimexExtensions.get_elapased_timestamp(workflow_info[:step_time])    
    workflow_step_durations = Map.put(workflow_step_durations, to_string(workflow_info[:current_step]), timestamp)
    workflow_info = Map.put(workflow_info, :workflow_step_durations, workflow_step_durations)
    workflow_info = send_success_notification(workflow_info, "Completed Workflow Milestone:  #{inspect workflow_info[:current_step]}, in #{timestamp}")    

    Agent.update(workflow, fn _ -> workflow_info end)
    save(workflow)
  end
end