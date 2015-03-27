#
# == message_manager.ex
#
# This module contains the logic for associating message references with their subscription handlers
#
require Logger

defmodule CloudOS.WorkflowOrchestrator.MessageManager do

  @moduledoc """
  This module contains the logic for associating message references with their subscription handlers
  """  

  @doc """
  Creates a `GenServer` representing Docker host cluster.

  ## Return values
  {:ok, pid} | {:error, String.t()}
  """
  @spec create() :: {:ok, pid} | {:error, String.t()}	
  def create() do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def track(%{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = _async_info) do
    message = %{
      process: self(),
      subscription_handler: subscription_handler, 
      delivery_tag: delivery_tag,
      start_time: :calendar.universal_time
    }
    Agent.update(__MODULE__, fn messages -> Map.put(messages, delivery_tag, message) end)
  end

  def remove(delivery_tag) do
    message = Agent.get(__MODULE__, fn messages -> messages[delivery_tag] end)
    Agent.update(__MODULE__, fn messages -> Map.delete(messages, delivery_tag) end)

    message
  end
end