#
# == dispatcher.ex
#
# This module contains the logic to dispatch WorkflowOrchestrator messsages to the appropriate GenServer(s)
#
require Logger

defmodule OpenAperture.WorkflowOrchestrator.Dispatcher do
	use GenServer

	alias OpenAperture.Messaging.AMQP.ConnectionOptions, as: AMQPConnectionOptions
  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  alias OpenAperture.WorkflowOrchestrator.MessageManager
  alias OpenAperture.WorkflowOrchestrator.Configuration
  alias OpenAperture.WorkflowOrchestrator.WorkflowFSM

  alias OpenAperture.WorkflowOrchestrator.MessageManager

  alias OpenAperture.ManagerApi

  @moduledoc """
  This module contains the logic to dispatch WorkflowOrchestrator messsages to the appropriate GenServer(s) 
  """  

	@connection_options nil
	use OpenAperture.Messaging

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
        Logger.error("Failed to start OpenAperture WorkflowOrchestrator:  #{inspect reason}")
        {:error, reason}
    	{:ok, pid} ->
        try do
          if Application.get_env(:autostart, :register_queues, false) do
        		case register_queues do
              {:ok, _} -> {:ok, pid}
              {:error, reason} -> 
                Logger.error("Failed to register WorkflowOrchestrator queues:  #{inspect reason}")
                {:ok, pid}
            end    		
          else
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
    workflow_orchestration_queue = QueueBuilder.build(ManagerApi.get_api, "workflow_orchestration", Configuration.get_current_exchange_id)

    options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, Configuration.get_current_broker_id)
    subscribe(options, workflow_orchestration_queue, fn(payload, _meta, %{delivery_tag: delivery_tag} = async_info) -> 
      Logger.debug("Received message #{delivery_tag}")
      try do
        try do
          MessageManager.track(async_info)
          execute_orchestration(payload, delivery_tag) 
        catch :exit, _ -> 
          Logger.error("An exit event was caught while occurred processing request #{delivery_tag}")
          acknowledge(delivery_tag)
        end        
      rescue e ->
        Logger.error("An exception occurred while processing request #{delivery_tag}:  #{inspect e}")
        acknowledge(delivery_tag)
      end
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
          Logger.debug("Successfully processed request #{inspect payload[:id]}")
        else
          Logger.error("Payload failed to process request #{inspect payload[:id]}:  #{inspect result}")
        end
      {:error, reason} -> 
        #raise an exception to kick the to another orchestrator (hopefully that can process it)
        raise "Unable to process request #{inspect payload[:id]}:  #{inspect reason}"
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