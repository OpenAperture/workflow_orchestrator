#
# == docker_host_resolver.ex
#
# This module contains the logic to resolve a Docker build cluster
#
require Logger

defmodule OpenAperture.WorkflowOrchestrator.Builder.DockerHostResolver do
	use GenServer

  @moduledoc """
  This module contains the logic to resolve a Docker build cluster
  """  

  alias OpenAperture.WorkflowOrchestrator.Configuration
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.EtcdCluster
  alias OpenAperture.ManagerApi.MessagingExchange  

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
  Method to retrieve the next available cluster from an available docker build clusters

  ## Return Values

  Returns a tuple containing {messaging_exchange_id, etcd_cluster}
  """
  @spec next_available() :: {String.t(), Map}
  def next_available() do
  	GenServer.call(__MODULE__, {:next_available})
  end

  @doc """
  Call handler to set the a value stored within the workflow server

  ## Options

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state
  
  ## Return Values

  {:reply, {messaging_exchange_id, machine}, resolved_state}
  """
  @spec handle_call({:next_available}, term, Map) :: {:reply, {String.t(), Map}, Map}
  def handle_call({:next_available}, _from, state) do
    {docker_build_clusters, resolved_state} = get_build_clusters(state)
    {:reply, get_exchange_cluster(docker_build_clusters), resolved_state}
  end

  @doc """
  Method to determine if the cached build clusters are stale (i.e. retrieved > 5 minutes prior)

  ## Return Values

  Boolean
  """
  @spec cache_stale?(Map) :: term
  def cache_stale?(state) do
    if state[:docker_build_clusters_retrieval_time] == nil do
      true
    else
      seconds = :calendar.datetime_to_gregorian_seconds(state[:docker_build_clusters_retrieval_time])
      now_seconds = :calendar.datetime_to_gregorian_seconds(:calendar.universal_time)
      (now_seconds - seconds) > 300
    end
  end

  @doc """
  Method to retrieve build clusters, from cache if possible

  ## Return Values

  {List of {messaging_exchange_id, cluster}, state}
  """
  @spec get_build_clusters(Map) :: {List, Map}
  def get_build_clusters(state) do
    unless state[:docker_build_clusters] == nil || cache_stale?(state) do
      {state[:docker_build_clusters], state}
    else
      docker_build_clusters = case get_local_build_clusters do
        nil -> get_global_build_clusters
        [] -> get_global_build_clusters        
        docker_build_clusters -> docker_build_clusters
      end
      state = Map.put(state, :docker_build_clusters, docker_build_clusters)
      state = Map.put(state, :docker_build_clusters_retrieval_time, :calendar.universal_time)
      {state[:docker_build_clusters], state}
    end
  end

  @doc """
  Method to retrieve build clusters in the current exchange

  ## Return Values

  List of {messaging_exchange_id, cluster}
  """
  @spec get_local_build_clusters :: List
  def get_local_build_clusters do
    #1.  Lookup any clusters that exist in the current exchange
    Logger.debug("Looking for build clusters in exchange #{Configuration.get_current_exchange_id}...")
    case MessagingExchange.exchange_clusters!(ManagerApi.get_api, Configuration.get_current_exchange_id, %{allow_docker_builds: true}) do
      nil -> nil
      [] -> nil
      docker_build_clusters -> 
        Enum.reduce docker_build_clusters, [], fn(cluster, exchange_clusters) ->
          exchange_clusters ++ [{cluster["messaging_exchange_id"], cluster}]
        end
    end
  end

  @doc """
  Method to retrieve all known build clusters

  ## Return Values

  List of {messaging_exchange_id, cluster}
  """
  @spec get_global_build_clusters :: List
  def get_global_build_clusters do
    #2.  If no clusters are availabe in the exchange, check globally for clusters
    Logger.debug("No build clusters are available in exchange #{Configuration.get_current_exchange_id}, checking globally...")
    case EtcdCluster.list!(ManagerApi.get_api, %{allow_docker_builds: true}) do
      nil -> nil
      [] -> nil
      docker_build_clusters -> 
        Enum.reduce docker_build_clusters, [], fn(cluster, exchange_clusters) ->
          exchange_clusters ++ [{cluster["messaging_exchange_id"], cluster}]
        end
    end    
  end

  @doc """
  Method to resolve to a single cluster for use.

  ## Options

  The `docker_build_clusters` option represents a List of tuples, each tuple consisting of
  {messaging_exchange_id, etcd_cluster}.  messaging_exchange_id is a String, etcd_cluster is a Map

  ## Return Values

  {messaging_exchange_id, cluster}
  """
  @spec get_exchange_cluster(List) :: {String.t(), Map}
  def get_exchange_cluster(docker_build_clusters) do
    if docker_build_clusters == nil || length(docker_build_clusters) == 0 do
      {nil, nil}
    else
      idx = :random.uniform(length(docker_build_clusters))-1
      {exchange_cluster, _} = Enum.reduce docker_build_clusters, {nil, 0}, fn (exchange_cluster, {etcd_token, cur_idx}) ->
        if cur_idx == idx do
          {exchange_cluster, cur_idx+1}
        else
          {etcd_token, cur_idx+1}
        end
      end

      exchange_cluster
    end
  end
end