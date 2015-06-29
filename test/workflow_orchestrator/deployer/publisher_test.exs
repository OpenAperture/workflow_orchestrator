defmodule OpenAperture.WorkflowOrchestrator.Deployer.PublisherTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias OpenAperture.WorkflowOrchestrator.Deployer.Publisher, as: DeployerPublisher
  alias OpenAperture.WorkflowOrchestrator.Dispatcher
  alias OpenAperture.Messaging.ConnectionOptionsResolver
  alias OpenAperture.Messaging.AMQP.ConnectionOptions, as: AMQPConnectionOptions

  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.AMQP.ConnectionPool
  alias OpenAperture.Messaging.AMQP.ConnectionPools

  setup_all _context do
    :meck.new(OpenAperture.Auth.Client, [:passthrough])
    :meck.expect(OpenAperture.Auth.Client, :get_token, fn _, _, _ -> "abc" end)

    on_exit _context, fn ->
      try do
        :meck.unload OpenAperture.Auth.Client
      rescue _ -> IO.puts "" end
    end    
    :ok
  end
  
  #=========================
  # start_link tests

  test "start_link - success" do
    assert DeployerPublisher.start_link != nil
  end

  #=========================
  # handle_cast({:deploy}) tests

  test "handle_cast({:deploy}) - success" do
    use_cassette "load_connection_options", custom: true do
      :meck.new(ConnectionPools, [:passthrough])
      :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

      :meck.new(ConnectionPool, [:passthrough])
      :meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> :ok end)    

      :meck.new(Dispatcher, [:passthrough])
      :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)

      :meck.new(QueueBuilder, [:passthrough])
      :meck.expect(QueueBuilder, :build, fn _,_,_ -> %OpenAperture.Messaging.Queue{name: ""} end)      

      :meck.new(ConnectionOptionsResolver, [:passthrough])
      :meck.expect(ConnectionOptionsResolver, :resolve, fn _, _, _, _ -> %AMQPConnectionOptions{} end)

      state = %{
      }

      payload = %{
      }

      assert DeployerPublisher.handle_cast({:deploy, "delivery_tag", "messaging_exchange_id", payload}, state) == {:noreply, state}
    end
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
    :meck.unload(Dispatcher)
    :meck.unload(QueueBuilder)
    :meck.unload(ConnectionOptionsResolver)    
  end

  test "handle_cast({:deploy}) - failure" do
    use_cassette "load_connection_options", custom: true do
      :meck.new(ConnectionPools, [:passthrough])
      :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

      :meck.new(ConnectionPool, [:passthrough])
      :meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> {:error, "bad news bears"} end)    

      :meck.new(Dispatcher, [:passthrough])
      :meck.expect(Dispatcher, :reject, fn _ -> :ok end)

      :meck.new(QueueBuilder, [:passthrough])
      :meck.expect(QueueBuilder, :build, fn _,_,_ -> %OpenAperture.Messaging.Queue{name: ""} end)      

      :meck.new(ConnectionOptionsResolver, [:passthrough])
      :meck.expect(ConnectionOptionsResolver, :resolve, fn _, _, _, _ -> %AMQPConnectionOptions{} end)      

      state = %{
      }

      payload = %{
      }

      assert DeployerPublisher.handle_cast({:deploy, "delivery_tag", "messaging_exchange_id", payload}, state) == {:noreply, state}
    end
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
    :meck.unload(Dispatcher)
    :meck.unload(QueueBuilder)
    :meck.unload(ConnectionOptionsResolver)    
  end  

  #=========================
  # handle_cast({:deploy_oa}) tests

  test "handle_cast({:deploy_oa}) - success" do
    use_cassette "load_connection_options", custom: true do
      :meck.new(ConnectionPools, [:passthrough])
      :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

      :meck.new(ConnectionPool, [:passthrough])
      :meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> :ok end)    

      :meck.new(Dispatcher, [:passthrough])
      :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)

      :meck.new(QueueBuilder, [:passthrough])
      :meck.expect(QueueBuilder, :build, fn _,_,_ -> %OpenAperture.Messaging.Queue{name: ""} end)      

      :meck.new(ConnectionOptionsResolver, [:passthrough])
      :meck.expect(ConnectionOptionsResolver, :resolve, fn _, _, _, _ -> %AMQPConnectionOptions{} end)

      state = %{
      }

      payload = %{
      }

      assert DeployerPublisher.handle_cast({:deploy_oa, "delivery_tag", "messaging_exchange_id", payload}, state) == {:noreply, state}
    end
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
    :meck.unload(Dispatcher)
    :meck.unload(QueueBuilder)
    :meck.unload(ConnectionOptionsResolver)    
  end

  test "handle_cast({:deploy_oa}) - failure" do
    use_cassette "load_connection_options", custom: true do
      :meck.new(ConnectionPools, [:passthrough])
      :meck.expect(ConnectionPools, :get_pool, fn _ -> %{} end)

      :meck.new(ConnectionPool, [:passthrough])
      :meck.expect(ConnectionPool, :publish, fn _, _, _, _ -> {:error, "bad news bears"} end)    

      :meck.new(Dispatcher, [:passthrough])
      :meck.expect(Dispatcher, :reject, fn _ -> :ok end)

      :meck.new(QueueBuilder, [:passthrough])
      :meck.expect(QueueBuilder, :build, fn _,_,_ -> %OpenAperture.Messaging.Queue{name: ""} end)      

      :meck.new(ConnectionOptionsResolver, [:passthrough])
      :meck.expect(ConnectionOptionsResolver, :resolve, fn _, _, _, _ -> %AMQPConnectionOptions{} end)      

      state = %{
      }

      payload = %{
      }

      assert DeployerPublisher.handle_cast({:deploy_oa, "delivery_tag", "messaging_exchange_id", payload}, state) == {:noreply, state}
    end
  after
    :meck.unload(ConnectionPool)
    :meck.unload(ConnectionPools)
    :meck.unload(Dispatcher)
    :meck.unload(QueueBuilder)
    :meck.unload(ConnectionOptionsResolver)    
  end   
end