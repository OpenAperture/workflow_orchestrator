#
# == publisher.ex
#
# This module contains the logic to publish messages to the Notifications system module
# It is assumes that a Notifications module is running in the same exchanges 
# as the Workflow Orchestrator
#
require Logger

defmodule OpenAperture.WorkflowOrchestrator.Notifications.Publisher do
	use GenServer

  @moduledoc """
  This module contains the logic to publish messages to the Notifications system module
  """  

	alias OpenAperture.Messaging.AMQP.QueueBuilder

	alias OpenAperture.WorkflowOrchestrator.Configuration

  alias OpenAperture.ManagerApi

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
  Method to publish a email notification

  ## Options

  The `exchange_id` option defines the exchange in which Notification messages should be sent

  The `broker_id` option defines the broker to which the Notification messages should be sent

  The `subject` option defines the email subject

  The `message` option defines the body of the email

  The `recipients` option defines an array of email addresses of recipients

  ## Return Values

  :ok | {:error, reason}   
  """
  @spec email_notification(String.t, String.t(), List) :: :ok | {:error, String.t()}
  def email_notification(subject, message, recipients) do
    payload = %{
      prefix: subject,
      message: message, 
      notifications: %{email_addresses: recipients}
    }

    GenServer.cast(__MODULE__, {:email, payload})
  end  

  @doc """
  Publishes a notification, via an asynchronous request to the `server`.
  
  ## Options

  The `notification_type` option defines an atom representing what type of notification should be sent (i.e. :hipchat, :email)

  The `payload` option defines the Hipchat Notification payload that should be sent

  The `state` option represents the server's current state
  
  ## Return Values

  {:noreply, state}

  """
  @spec handle_cast({term, Map}, Map) :: {:noreply, Map}
  def handle_cast({notification_type, payload}, state) do
    notification_type_string = to_string(notification_type)
    queue = QueueBuilder.build(ManagerApi.get_api, "notifications_#{notification_type_string}", Configuration.get_current_exchange_id)

    options = OpenAperture.Messaging.ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, Configuration.get_current_broker_id)
		case publish(options, queue, payload) do
			:ok -> Logger.debug("Successfully published #{notification_type_string} notification")
			{:error, reason} -> Logger.error("Failed to publish #{notification_type_string} notification:  #{inspect reason}")
		end
    {:noreply, state}
  end
end