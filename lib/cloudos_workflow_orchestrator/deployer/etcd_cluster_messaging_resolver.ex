#
# == docker_host_resolver.ex
#
# This module contains the logic to resolve a Docker build host
#
require Logger

defmodule CloudOS.WorkflowOrchestrator.Deployer.EtcdClusterMessagingResolver do
	use GenServer

  alias CloudOS.WorkflowOrchestrator.Configuration
  alias CloudOS.ManagerAPI
  alias CloudOS.ManagerAPI.EtcdCluster
  alias CloudOS.ManagerAPI.MessagingExchange  

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
  Method to retrieve the next available host from an available docker cluster

  ## Return Values

  Returns a tuple containing {messaging_exchange_id, etcd_cluster}
  """
  @spec exchange_for_cluster(String.t()) :: {String.t(), Map}
  def exchange_for_cluster(etcd_token) do
  	GenServer.call(__MODULE__, {:exchange_for_cluster, etcd_token})
  end

  @doc """
  Call handler to set the a value stored within the workflow server

  ## Options

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state
  
  ## Return Values

  {:reply, {messaging_exchange_id, machine}, resolved_state}
  """
  @spec handle_call({:exchange_for_cluster, String.t()}, term, Map) :: {:reply, {String.t(), Map}, Map}
  def handle_call({:exchange_for_cluster, etcd_token}, _from, state) do
    {:reply, get_exchange_for_cluster(etcd_token), state}
  end

  @doc """
  Method to retrieve build clusters in the current exchange

  ## Return Values

  List of {messaging_exchange_id, cluster}
  """
  @spec get_exchange_for_cluster(Map) :: List
  def get_exchange_for_cluster(etcd_token) do
    case EtcdCluster.get_cluster!(ManagerAPI.get_api, etcd_token) do
      nil -> nil
      cluster -> cluster["messaging_exchange_id"]
    end
  end    
end