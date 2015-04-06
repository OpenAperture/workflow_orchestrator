defmodule CloudOS.WorkflowOrchestrator.Deployer.EtcdClusterMessagingResolverTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias CloudOS.WorkflowOrchestrator.Deployer.EtcdClusterMessagingResolver

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
  # get_exchange_for_cluster tests

  test "get_exchange_for_cluster - success" do
    use_cassette "get_cluster", custom: true do
      assert EtcdClusterMessagingResolver.get_exchange_for_cluster("123abc") == 1
    end
  end

  test "get_exchange_for_cluster - success no id" do
    use_cassette "get_cluster-no-messaging", custom: true do
      assert EtcdClusterMessagingResolver.get_exchange_for_cluster("123abc") == nil
    end
  end

  test "get_exchange_for_cluster - failure" do
    use_cassette "get_cluster_failure", custom: true do
      assert EtcdClusterMessagingResolver.get_exchange_for_cluster("123abc") == nil
    end
  end
  
  #=========================
  # handle_call({:exchange_for_cluster}) tests


  test "handle_call({:exchange_for_cluster}) - success" do
    use_cassette "get_cluster", custom: true do
      state = %{}
      assert EtcdClusterMessagingResolver.handle_call({:exchange_for_cluster, "123abc"}, %{}, state) == {:reply, 1, state}
    end
  end  
end