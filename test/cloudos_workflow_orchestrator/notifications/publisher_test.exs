defmodule CloudOS.WorkflowOrchestrator.Notifications.PublisherTest do
  use ExUnit.Case

  alias CloudOS.WorkflowOrchestrator.Notifications.Publisher
  alias CloudOS.Messaging.ConnectionOptionsResolver
  alias CloudOS.Messaging.AMQP.ConnectionOptions, as: AMQPConnectionOptions

  alias CloudOS.Messaging.AMQP.QueueBuilder
  alias CloudOS.Messaging.AMQP.ConnectionPool
  alias CloudOS.Messaging.AMQP.ConnectionPools

  #=========================
  # handle_cast({:hipchat, payload}) tests

  test "handle_cast({:hipchat, payload}) - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> :ok end)

    :meck.new(QueueBuilder, [:passthrough])
    :meck.expect(QueueBuilder, :build, fn _,_,_ -> %CloudOS.Messaging.Queue{name: ""} end)      

    :meck.new(ConnectionOptionsResolver, [:passthrough])
    :meck.expect(ConnectionOptionsResolver, :get_for_broker, fn _, _ -> %AMQPConnectionOptions{} end)

  	state = %{
  	}

  	payload = %{
			is_success: true,
			prefix: "[Test Prefix]",
			message: "testing message"	
  	}
    assert Publisher.handle_cast({:hipchat, payload}, state) == {:noreply, state}
  after
  	:meck.unload(ConnectionPool)
  	:meck.unload(ConnectionPools)
    :meck.unload(QueueBuilder)
    :meck.unload(ConnectionOptionsResolver)        
  end
end
