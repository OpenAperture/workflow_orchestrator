defmodule CloudOS.WorkflowOrchestrator.Notifications.PublisherTest do
  use ExUnit.Case

  alias CloudOS.WorkflowOrchestrator.Notifications.Publisher

  alias CloudOS.Messaging.AMQP.ConnectionPool
  alias CloudOS.Messaging.AMQP.ConnectionPools

  #=========================
  # handle_cast({:hipchat, payload}) tests

  test "handle_cast({:hipchat, payload}) - success" do
  	:meck.new(ConnectionPools, [:passthrough])
  	:meck.expect(ConnectionPools, :get_pool, fn opts -> %{} end)

  	:meck.new(ConnectionPool, [:passthrough])
  	:meck.expect(ConnectionPool, :publish, fn pool, exchange, queue, payload -> :ok end)

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
  end
end
