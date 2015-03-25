#
# == notifications.ex
#
# This module contains the logic to publish messages to the Notifications system module
# It is assumes that a Notifications module is running in the same exchanges 
# as the Workflow Orchestrator
#
require Logger

defmodule CloudOS.WorkflowOrchestrator.Notifications.Publisher do
	use GenServer

  @moduledoc """
  This module contains the logic to publish messages to the Notifications system module
  """  

	alias CloudOS.Messaging.AMQP.ConnectionOptions, as: AMQPConnectionOptions
	alias CloudOS.Messaging.AMQP.Exchange, as: AMQPExchange
	alias CloudOS.Messaging.Queue

	alias CloudOS.WorkflowOrchestrator.Configuration

	@hipchat_queue %Queue{
    name: "notifications_hipchat", 
    exchange: %AMQPExchange{name: Configuration.get_messaging_config("MESSAGING_EXCHANGE", :exchange), failover_name: Configuration.get_messaging_config("FAILOVER_MESSAGING_EXCHANGE", :failover_exchange), options: [:durable]},
    error_queue: "notifications_error",
    options: [durable: true, arguments: [{"x-dead-letter-exchange", :longstr, ""},{"x-dead-letter-routing-key", :longstr, "notifications_error"}]],
    binding_options: [routing_key: "notifications_hipchat"]
  }

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
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Method to publish a hipchat notification

  ## Options

  The `is_success` option is a boolean that determines success

  The `prefix` option is the message prefix String

  The `message` option is the message content

  The `room_names` option is (optionally) HipChat room names to publish to

  ## Return Values

  :ok | {:error, reason}   
  """
  @spec hipchat_notification(term, String.t(), String.t(), List) :: :ok | {:error, String.t()}
  def hipchat_notification(is_success, prefix, message, room_names \\ nil) do
		payload = %{
			is_success: is_success,
			prefix: prefix,
			message: message,
			room_names: room_names
		}

  	GenServer.cast(__MODULE__, {:hipchat, payload})
  end

  @doc """
  Publishes a HipChat notification, via an asynchronous request to the `server`.

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
  @spec handle_cast({:hipchat, Map}, Map) :: {:noreply, Map}
  def handle_cast({:hipchat, payload}, state) do
		case publish(@hipchat_queue, payload) do
			:ok -> Logger.debug("Successfully published HipChat notification")
			{:error, reason} -> Logger.error("Failed to publish HipChat notification:  #{inspect reason}")
		end
    {:noreply, state}
  end
end