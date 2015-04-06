defmodule CloudOS.WorkflowOrchestrator.DispatcherTests do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc

  alias CloudOS.WorkflowOrchestrator.Dispatcher

  alias CloudOS.Messaging.AMQP.ConnectionPool
  alias CloudOS.Messaging.AMQP.ConnectionPools
  alias CloudOS.Messaging.AMQP.SubscriptionHandler

  alias CloudOS.WorkflowOrchestrator.WorkflowFSM
  alias CloudOS.WorkflowOrchestrator.MessageManager
  
  # ===================================
  # register_queues tests

  test "register_queues success" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> :ok end)

    assert Dispatcher.register_queues == :ok
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
  end

  test "register_queues failure" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> {:error, "bad news bears"} end)

    assert Dispatcher.register_queues == {:error, "bad news bears"}
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
  end  

  # ===================================
  # execute_orchestration tests

  test "execute_orchestration - success" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> :ok end)

    :meck.new(WorkflowFSM, [:passthrough])
    :meck.expect(WorkflowFSM, :start_link, fn _, _ -> {:ok, nil} end)    
    :meck.expect(WorkflowFSM, :execute, fn _ -> :ok end)

    payload = %{
    }
    Dispatcher.execute_orchestration(payload, %{subscription_handler: %{}, delivery_tag: "123abc"})
  after
    :meck.unload(WorkflowFSM)
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
  end

  test "execute_orchestration - failure" do
    :meck.new(ConnectionPools, [:passthrough])
    :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

    :meck.new(ConnectionPool, [:passthrough])
    :meck.expect(ConnectionPool, :subscribe, fn _, _, _, _ -> :ok end)

    :meck.new(WorkflowFSM, [:passthrough])
    :meck.expect(WorkflowFSM, :start_link, fn _, _ -> {:ok, nil} end)    
    :meck.expect(WorkflowFSM, :execute, fn _ -> {:error, "bad news bears"} end)

    payload = %{
    }
    Dispatcher.execute_orchestration(payload, %{subscription_handler: %{}, delivery_tag: "123abc"})
  after
    :meck.unload(WorkflowFSM)
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
  end  

  test "acknowledge" do
    :meck.new(MessageManager, [:passthrough])
    :meck.expect(MessageManager, :remove, fn _ -> %{} end)

    :meck.new(SubscriptionHandler, [:passthrough])
    :meck.expect(SubscriptionHandler, :acknowledge, fn _, _ -> :ok end)

    Dispatcher.acknowledge("123abc")
  after
    :meck.unload(MessageManager)
    :meck.unload(SubscriptionHandler)
  end

  test "reject" do
    :meck.new(MessageManager, [:passthrough])
    :meck.expect(MessageManager, :remove, fn _ -> %{} end)

    :meck.new(SubscriptionHandler, [:passthrough])
    :meck.expect(SubscriptionHandler, :reject, fn _, _, _ -> :ok end)

    Dispatcher.reject("123abc")
  after
    :meck.unload(MessageManager)
    :meck.unload(SubscriptionHandler)
  end  
end