#
# == message_manager.ex
#
# This module contains the logic for associating message references with their subscription handlers
# Future development may utilize this manager to clear out expired messages.
#
require Logger

defmodule OpenAperture.WorkflowOrchestrator.MessageManager do

  #alias OpenAperture.OverseerApi.Heartbeat

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
    new_message = %{
      process: self(),
      subscription_handler: subscription_handler, 
      delivery_tag: delivery_tag,
      start_time: :calendar.universal_time
    }

    messages = Agent.get(__MODULE__, fn messages -> messages end)
    messages = Map.put(messages, delivery_tag, new_message)

    # workload = Enum.reduce Map.keys(messages), [], fn(delivery_tag, workload) ->
    #   workload ++ [%{
    #     description: "Request:  #{delivery_tag}"
    #   }]
    # end
    #Heartbeat.set_workload(workload)

    Agent.update(__MODULE__, fn _ -> messages end)

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
    messages = Agent.get(__MODULE__, fn messages -> messages end)
    deleted_message = messages[delivery_tag]
    messages = Map.delete(messages, delivery_tag)
    
    # workload = Enum.reduce Map.keys(messages), [], fn(delivery_tag, workload) ->
    #   workload ++ [%{
    #     description: "Request:  #{delivery_tag}"
    #   }]
    # end
    #Heartbeat.set_workload(workload)

    Agent.update(__MODULE__, fn _ -> messages end)
    deleted_message
  end
end