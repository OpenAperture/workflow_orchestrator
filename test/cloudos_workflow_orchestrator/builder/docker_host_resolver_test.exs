defmodule CloudOS.WorkflowOrchestrator.Builder.DockerHostResolverTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias CloudOS.WorkflowOrchestrator.Builder.DockerHostResolver

  alias CloudOS.Messaging.AMQP.ConnectionPool
  alias CloudOS.Messaging.AMQP.ConnectionPools

  #=========================
  # get_host_for_cluster tests

  test "get_host_for_cluster - success no machines" do
    use_cassette "get_cluster_machines-empty", custom: true do
      messaging_exchange_id = "123"
      cluster = %{
        "etcd_token" => "123abc"
      }
      assert DockerHostResolver.get_host_for_cluster({messaging_exchange_id, cluster}) == {messaging_exchange_id, nil}
    end
  end

  test "get_host_for_cluster - success machines" do
    use_cassette "get_cluster_machines", custom: true do
      messaging_exchange_id = "123"
      cluster = %{
        "etcd_token" => "123abc"
      }
      {return_messaging_exchange_id, return_machine} = DockerHostResolver.get_host_for_cluster({messaging_exchange_id, cluster})

      assert return_messaging_exchange_id == messaging_exchange_id
      assert return_machine != nil
      assert return_machine["primaryIP"] != nil
      assert (return_machine["primaryIP"] == "123.234.456.789" || return_machine["primaryIP"] == "000.000.000.000")
    end
  end

  test "get_host_for_cluster - failure" do
    use_cassette "get_cluster_machines_failure", custom: true do
      messaging_exchange_id = "123"
      cluster = %{
        "etcd_token" => "123abc"
      }
      assert DockerHostResolver.get_host_for_cluster({messaging_exchange_id, cluster}) == {messaging_exchange_id, nil}
    end
  end

  #=========================
  # get_host_from_cluster tests

  test "get_host_from_cluster - success no machines" do
    use_cassette "get_cluster_machines-empty", custom: true do
      messaging_exchange_id = "123"
      cluster = %{
        "etcd_token" => "123abc"
      }
      assert DockerHostResolver.get_host_from_cluster([{messaging_exchange_id, cluster}]) == {messaging_exchange_id, nil}
    end
  end

  test "get_host_from_cluster - success machines" do
    use_cassette "get_cluster_machines", custom: true do
      messaging_exchange_id = "123"
      cluster = %{
        "etcd_token" => "123abc"
      }
      {return_messaging_exchange_id, return_machine} = DockerHostResolver.get_host_from_cluster([{messaging_exchange_id, cluster}])

      assert return_messaging_exchange_id == messaging_exchange_id
      assert return_machine != nil
      assert return_machine["primaryIP"] != nil
      assert (return_machine["primaryIP"] == "123.234.456.789" || return_machine["primaryIP"] == "000.000.000.000")
    end
  end

  test "get_host_from_cluster - no clusters" do
    use_cassette "get_cluster_machines_failure", custom: true do
      assert DockerHostResolver.get_host_from_cluster([]) == {nil, nil}
    end
  end

  test "get_host_from_cluster - failure" do
    use_cassette "get_cluster_machines_failure", custom: true do
      messaging_exchange_id = "123"
      cluster = %{
        "etcd_token" => "123abc"
      }
      assert DockerHostResolver.get_host_from_cluster([{messaging_exchange_id, cluster}]) == {messaging_exchange_id, nil}
    end
  end    

  #=========================
  # get_global_build_clusters tests

  test "get_global_build_clusters - success no clusters" do
    use_cassette "list_clusters-empty", custom: true do
      assert DockerHostResolver.get_global_build_clusters == nil
    end
  end

  test "get_global_build_clusters - success clusters" do
    use_cassette "list_clusters", custom: true do
      clusters = DockerHostResolver.get_global_build_clusters

      assert clusters != nil
      assert length(clusters) == 2
      is_successful = Enum.reduce clusters, true, fn({_messaging_exchange_id, cluster}, is_successful) ->
        if is_successful do
          cond do
            cluster["id"] == 1 && cluster["etcd_token"] == "123abc" -> true
            cluster["id"] == 2 && cluster["etcd_token"] == "789xyz" -> true
            true -> false
          end
        else
          is_successful
        end
      end
      assert is_successful
    end
  end

  test "get_global_build_clusters - failure" do
    use_cassette "list_clusters_failure", custom: true do
      assert DockerHostResolver.get_global_build_clusters == nil
    end
  end  

#=========================
  # get_local_build_clusters tests

  test "get_local_build_clusters - success no clusters" do
    use_cassette "exchange_clusters-empty", custom: true do
      assert DockerHostResolver.get_local_build_clusters == nil
    end
  end

  test "get_local_build_clusters - success clusters" do
    use_cassette "exchange_clusters", custom: true do
      clusters = DockerHostResolver.get_local_build_clusters

      assert clusters != nil
      assert length(clusters) == 2
      is_successful = Enum.reduce clusters, true, fn({_messaging_exchange_id, cluster}, is_successful) ->
        if is_successful do
          cond do
            cluster["id"] == 1 && cluster["etcd_token"] == "123abc" -> true
            cluster["id"] == 2 && cluster["etcd_token"] == "789xyz" -> true
            true -> false
          end
        else
          is_successful
        end
      end
      assert is_successful
    end
  end

  test "get_local_build_clusters - failure" do
    use_cassette "exchange_clusters_failure", custom: true do
      assert DockerHostResolver.get_local_build_clusters == nil
    end
  end 

  #=========================
  # get_build_clusters tests

  test "get_build_clusters - success local clusters" do
    use_cassette "get_build_clusters-local-success", custom: true do
      state = %{}
      {exchange_clusters, returned_state} = DockerHostResolver.get_build_clusters(state)

      assert returned_state != nil
      assert returned_state[:docker_build_clusters] != nil
      assert returned_state[:docker_build_clusters_retrieval_time] != nil

      assert exchange_clusters != nil
      assert exchange_clusters == returned_state[:docker_build_clusters]
      assert length(exchange_clusters) == 2
      is_successful = Enum.reduce exchange_clusters, true, fn({_messaging_exchange_id, cluster}, is_successful) ->
        if is_successful do
          cond do
            cluster["id"] == 1 && cluster["etcd_token"] == "123abc" -> true
            cluster["id"] == 2 && cluster["etcd_token"] == "789xyz" -> true
            true -> false
          end
        else
          is_successful
        end
      end
      assert is_successful
    end
  end

  test "get_build_clusters - success global clusters" do
    use_cassette "get_build_clusters-global-success", custom: true do
      state = %{}
      {exchange_clusters, returned_state} = DockerHostResolver.get_build_clusters(state)

      assert returned_state != nil
      assert returned_state[:docker_build_clusters] != nil
      assert returned_state[:docker_build_clusters_retrieval_time] != nil

      assert exchange_clusters != nil
      assert exchange_clusters == returned_state[:docker_build_clusters]
      assert length(exchange_clusters) == 2
      is_successful = Enum.reduce exchange_clusters, true, fn({_messaging_exchange_id, cluster}, is_successful) ->
        if is_successful do
          cond do
            cluster["id"] == 1 && cluster["etcd_token"] == "123abc" -> true
            cluster["id"] == 2 && cluster["etcd_token"] == "789xyz" -> true
            true -> false
          end
        else
          is_successful
        end
      end
      assert is_successful
    end
  end

  test "get_build_clusters - failure" do
    use_cassette "get_build_clusters-failure", custom: true do
      state = %{}
      {exchange_clusters, returned_state} = DockerHostResolver.get_build_clusters(state)

      assert exchange_clusters == nil
      assert returned_state != nil
      assert returned_state[:docker_build_clusters] == nil
      assert returned_state[:docker_build_clusters_retrieval_time] != nil
    end
  end 

  test "get_build_clusters - success cached" do
    state = %{
      docker_build_clusters_retrieval_time: :calendar.universal_time,
      docker_build_clusters: []
    }
    {exchange_clusters, returned_state} = DockerHostResolver.get_build_clusters(state)

    assert returned_state != nil
    assert returned_state[:docker_build_clusters] != nil
    assert returned_state[:docker_build_clusters_retrieval_time] != nil

    assert exchange_clusters != nil
    assert exchange_clusters == returned_state[:docker_build_clusters]
    assert length(exchange_clusters) == 0
  end  

  #=========================
  # cache_stale? tests

  test "cache_stale? - no time" do
    state = %{}
    DockerHostResolver.cache_stale?(state) == true
  end

  test "cache_stale? - expired" do
    seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)
    seconds = seconds - 301

    state = %{
      docker_build_clusters_retrieval_time: :calendar.gregorian_seconds_to_datetime(seconds)
    }
    DockerHostResolver.cache_stale?(state) == true
  end

  test "cache_stale? - valid" do
    state = %{
      docker_build_clusters_retrieval_time: :calendar.universal_time
    }
    DockerHostResolver.cache_stale?(state) == false
  end

  #=========================
  # handle_call({:next_available}) tests

  test "handle_call({:next_available}) - success" do
    use_cassette "next_available-success", custom: true do 
      state = %{}
      {:reply, {_messaging_exchange_id, return_machine}, returned_state} = DockerHostResolver.handle_call({:next_available}, %{}, state)

      assert returned_state != nil
      assert returned_state[:docker_build_clusters] != nil
      assert returned_state[:docker_build_clusters_retrieval_time] != nil      

      assert return_machine != nil
      assert return_machine["primaryIP"] != nil
      assert (return_machine["primaryIP"] == "123.234.456.789" || return_machine["primaryIP"] == "000.000.000.000")      
    end
  end

  test "handle_call({:next_available}) - failure" do
    use_cassette "next_available-failure", custom: true do
      state = %{}
      {:reply, {_messaging_exchange_id, return_machine}, returned_state} = DockerHostResolver.handle_call({:next_available}, %{}, state)

      assert return_machine == nil
      assert returned_state != nil
      assert returned_state[:docker_build_clusters] == nil
      assert returned_state[:docker_build_clusters_retrieval_time] != nil    
    end
  end  
end