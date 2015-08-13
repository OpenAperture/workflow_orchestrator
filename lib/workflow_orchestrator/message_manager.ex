#
# == message_manager.ex
#
# This module contains the logic for associating message references with their subscription handlers
# Future development may utilize this manager to clear out expired messages.
#
require Logger

defmodule OpenAperture.WorkflowOrchestrator.MessageManager do

  @logprefix "[MessageManager]"

  @moduledoc """
  This module contains the logic for associating message references with their subscription handlers
  """  

  @doc """
  Creates a `GenServer` representing Docker host cluster.

  ## Return values
  {:ok, pid} | {:error, String.t()}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}	
  def start_link() do
    Logger.debug("#{@logprefix} Starting...")      
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Method to start tracking a delivered message.

  ## Options

  The `_async_info` is a Map containing the following entries:
    * :subscription_handler
    * :delivery_tag
  """
  @spec track(Map) :: term
  def track(%{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = _async_info) do
    Logger.debug("#{@logprefix} Tracking message #{delivery_tag}...")    
    new_message = %{
      process: self(),
      subscription_handler: subscription_handler, 
      delivery_tag: delivery_tag,
      start_time: :calendar.universal_time
    }

    Agent.update(__MODULE__, fn messages -> Map.put(messages, delivery_tag, new_message) end)
    
    new_message
  end

  @doc """
  Method to stop tracking a delivered message

  ## Options

  The `delivery_tag` option is the unique identifier of the message

  ## Return Value

  Map containing the subscription_handler and delivery_tag
  """
  @spec remove(String.t()) :: Map
  def remove(delivery_tag) do
    Logger.debug("#{@logprefix} Finished tracking message #{delivery_tag}...")

    Agent.get_and_update(__MODULE__, fn messages ->
      message = messages[delivery_tag]
      {message, Map.delete(messages, delivery_tag)}
    end)
  end
end