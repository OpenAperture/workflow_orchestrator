#
# == dispatcher.ex
#
# This module contains the logic to dispatch WorkflowOrchestrator messsages to the appropriate GenServer(s)
#
require Logger

defmodule CloudOS.WorkflowOrchestrator.Dispatcher do
	use GenServer

	alias CloudOS.Messaging.AMQP.ConnectionOptions, as: AMQPConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange
	alias CloudOS.Messaging.Queue

  alias CloudOS.WorkflowOrchestrator.Configuration
  alias CloudOS.WorkflowOrchestrator.Workflow

  @moduledoc """
  This module contains the logic to dispatch WorkflowOrchestrator messsages to the appropriate GenServer(s) 
  """  

	@connection_options %AMQPConnectionOptions{
      username: Configuration.get_messaging_config("MESSAGING_USERNAME", :username),
      password: Configuration.get_messaging_config("MESSAGING_PASSWORD", :password),
      virtual_host: Configuration.get_messaging_config("MESSAGING_VIRTUAL_HOST", :virtual_host),
      host: Configuration.get_messaging_config("MESSAGING_HOST", :host)
    }
	use CloudOS.Messaging

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link do
    case GenServer.start_link(__MODULE__, %{}, name: __MODULE__) do
    	{:error, reason} -> 
        Logger.error("Failed to start CloudOS WorkflowOrchestrator:  #{inspect reason}")
        {:error, reason}
    	{:ok, pid} ->
        try do
      		case register_queues do
            :ok -> {:ok, pid}
            {:error, reason} -> 
              Logger.error("Failed to register WorkflowOrchestrator queues:  #{inspect reason}")
              {:ok, pid}
          end    		
        rescue e in _ ->
          Logger.error("An error occurred registering WorkflowOrchestrator queues:  #{inspect e}")
          {:ok, pid}
        end
    end
  end

  @doc """
  Method to register the WorkflowOrchestrator queues with the Messaging system

  ## Return Value

  :ok | {:error, reason}
  """
  @spec register_queues() :: :ok | {:error, String.t()}
  def register_queues do
    Logger.debug("Registering WorkflowOrchestrator queues...")

    milestone_queue = %Queue{
      name: "workflow_orchestration_milestone", 
      exchange: %AMQPExchange{name: Configuration.get_messaging_config("MESSAGING_EXCHANGE", :exchange), options: [:durable]},
      error_queue: "workflow_orchestration_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "workflow_orchestration_error"}]],
      binding_options: [routing_key: "workflow_orchestration_milestone"]
    }

    subscribe(milestone_queue, fn(payload, _meta) -> dispatch_milestone(payload) end)
  end

  @doc """
  Method to dispatch Workflow Milestones to the Workflow Orchestrator

  ## Options

  The `payload` option is the Map of HipChat options

  ## Return Value

  :ok | {:error, reason}
  """
  @spec dispatch_milestone(Map) :: :ok | {:error, String.t()}
  def dispatch_milestone(payload) do
    case Workflow.start_link(payload, %{}) do
      {:ok, workflow} ->
        #The start_link of the server will automatically kick off the state machine
        Logger.debug("Successfully processed payload")
      {:error, reason} -> 
        #raise an exception to kick the to another orchestrator (hopefully that can process it)
        raise "Unable to process Workflow Orchestration message:  #{inspect reason}"
    end
  end
end