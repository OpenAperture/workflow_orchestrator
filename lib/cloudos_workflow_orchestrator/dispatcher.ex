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
  alias CloudOS.Messaging.AMQP.SubscriptionHandler
  alias CloudOS.Messaging.Queue

  alias CloudOS.WorkflowOrchestrator.MessageManager
  alias CloudOS.WorkflowOrchestrator.Configuration
  alias CloudOS.WorkflowOrchestrator.WorkflowFSM

  alias CloudOS.WorkflowOrchestrator.MessageManager

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
      name: "workflow_orchestration", 
      exchange: %AMQPExchange{name: Configuration.get_messaging_config("MESSAGING_EXCHANGE", :exchange), options: [:durable]},
      error_queue: "workflow_orchestration_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "workflow_orchestration_error"}]],
      binding_options: [routing_key: "workflow_orchestration"]
    }

    subscribe(milestone_queue, fn(payload, _meta, %{delivery_tag: delivery_tag} = async_info) -> 
      MessageManager.track(async_info)
      execute_orchestration(payload, delivery_tag) 
    end)
  end

  @doc """
  Method to start Workflow Orchestrations

  ## Options

  The `payload` option is the Map of HipChat options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec execute_orchestration(Map, String.t()) :: term
  def execute_orchestration(payload, delivery_tag) do
    case WorkflowFSM.start_link(payload, delivery_tag) do
      {:ok, workflow} ->
        result = WorkflowFSM.execute(workflow)
        if result == :completed do
          Logger.debug("Successfully processed payload")
        else
          Logger.error("Payload failed to process correctly:  #{inspect result}")
        end
      {:error, reason} -> 
        #raise an exception to kick the to another orchestrator (hopefully that can process it)
        raise "Unable to process Workflow Orchestration message:  #{inspect reason}"
    end
  end

  @doc """
  Method to acknowledge a message has been processed

  ## Options

  The `delivery_tag` option is the unique identifier of the message
  """
  @spec acknowledge(String.t()) :: term
  def acknowledge(delivery_tag) do
    message = MessageManager.remove(delivery_tag)
    unless message == nil do
      SubscriptionHandler.acknowledge(message[:subscription_handler], message[:delivery_tag])
    end
  end

  @doc """
  Method to reject a message has been processed

  ## Options

  The `delivery_tag` option is the unique identifier of the message

  The `redeliver` option can be used to requeue a message
  """
  @spec reject(String.t(), term) :: term
  def reject(delivery_tag, redeliver \\ false) do
    message = MessageManager.remove(delivery_tag)
    unless message == nil do
      SubscriptionHandler.reject(message[:subscription_handler], message[:delivery_tag], redeliver)
    end
  end  
end