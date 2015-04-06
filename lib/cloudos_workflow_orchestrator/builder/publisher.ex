#
# == publisher.ex
#
# This module contains the logic to publish messages to the Builder system module
#
require Logger

defmodule CloudOS.WorkflowOrchestrator.Builder.Publisher do
	use GenServer

  @moduledoc """
  This module contains the logic to publish messages to the Builder system module
  """  

  alias CloudOS.Messaging.ConnectionOptionsResolver
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange
	alias CloudOS.Messaging.Queue

	alias CloudOS.WorkflowOrchestrator.Configuration
  alias CloudOS.WorkflowOrchestrator.Dispatcher

  alias CloudOS.ManagerAPI

	@connection_options nil
	use CloudOS.Messaging

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t()}   
  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Method to publish the Builder system module

  ## Options

  The `payload` option is the Map of options that needs to be passed to the build module

  ## Return Values

  :ok | {:error, reason}   
  """
  @spec build(String.t(), String.t(), term) :: :ok | {:error, String.t()}
  def build(delivery_tag, messaging_exchange_id, payload) do
   	GenServer.cast(__MODULE__, {:build, delivery_tag, messaging_exchange_id, payload})
  end

  @doc """
  Publishes a message to the Builder system module, via an asynchronous request to the `server`.

  This function returns `:ok` immediately, regardless of
  whether the destination node or server does exists, unless
  the server is specified as an atom.

  `handle_cast/2` will be called on the server to handle
  the request. In case the server is a node which is not
  yet connected to the caller one, the call is going to
  block until a connection happens. This is different than
  the behaviour in OTP's `:gen_server` where the message
  would be sent by another process, which could cause
  messages to arrive out of order.
  """
  @spec handle_cast({:build, String.t(), String.t(), Map}, Map) :: {:noreply, Map}
  def handle_cast({:build, delivery_tag, messaging_exchange_id, payload}, state) do
    build_queue = %Queue{
      name: "builder", 
      exchange: %AMQPExchange{name: messaging_exchange_id, options: [:durable]},
      error_queue: "builder_error",
      options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "builder_error"}]],
      binding_options: [routing_key: "builder"]
    }

    connection_options = ConnectionOptionsResolver.resolve(
      ManagerAPI.get_api, 
      Configuration.get_current_broker_id,
      Configuration.get_current_exchange_id,
      messaging_exchange_id
    )

		case publish(connection_options, build_queue, payload) do
			:ok -> 
        Logger.debug("Successfully published Builder message")
        Dispatcher.acknowledge(delivery_tag)
			{:error, reason} -> 
        Logger.error("Failed to publish Builder message:  #{inspect reason}")
        Dispatcher.reject(delivery_tag)
		end
    {:noreply, state}
  end
end