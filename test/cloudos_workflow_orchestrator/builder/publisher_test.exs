defmodule CloudOS.WorkflowOrchestrator.Builder.PublisherTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias CloudOS.WorkflowOrchestrator.Builder.Publisher, as: BuilderPublisher
  alias CloudOS.WorkflowOrchestrator.Dispatcher

  #alias CloudOS.Messaging.ConnectionOptionsResolver
  alias CloudOS.Messaging.AMQP.ConnectionPool
  alias CloudOS.Messaging.AMQP.ConnectionPools

  setup_all _context do
    :meck.new(CloudosAuth.Client, [:passthrough])
    :meck.expect(CloudosAuth.Client, :get_token, fn _, _, _ -> "abc" end)

    on_exit _context, fn ->
      try do
        :meck.unload CloudosAuth.Client
      rescue _ -> IO.puts "" end
    end    
    :ok
  end
  
  #=========================
  # start_link tests

  test "start_link - success" do
    assert BuilderPublisher.start_link != nil
  end

  #=========================
  # handle_cast({:build}) tests

  test "handle_cast({:build}) - success" do
    use_cassette "load_connection_options", custom: true do
      :meck.new(ConnectionPools, [:passthrough])
      :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

      :meck.new(ConnectionPool, [:passthrough])
      :meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> :ok end)    

      :meck.new(Dispatcher, [:passthrough])
      :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)

      state = %{
      }

      payload = %{
      }

      assert BuilderPublisher.handle_cast({:build, "delivery_tag", "messaging_exchange_id", payload}, state) == {:noreply, state}
    end
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
    :meck.unload(Dispatcher)
  end

  test "handle_cast({:build}) - failure" do
    use_cassette "load_connection_options", custom: true do
      :meck.new(ConnectionPools, [:passthrough])
      :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

      :meck.new(ConnectionPool, [:passthrough])
      :meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> {:error, "bad news bears"} end)    

      :meck.new(Dispatcher, [:passthrough])
      :meck.expect(Dispatcher, :reject, fn _ -> :ok end)

      state = %{
      }

      payload = %{
      }

      assert BuilderPublisher.handle_cast({:build, "delivery_tag", "messaging_exchange_id", payload}, state) == {:noreply, state}
    end
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
    :meck.unload(Dispatcher)
  end  
end