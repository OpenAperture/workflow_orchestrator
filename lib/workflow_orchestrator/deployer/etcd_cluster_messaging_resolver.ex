#
# == etcd_cluster_messaging_resolver.ex
#
# This module contains the logic to resolve the correct MessagingExchange for an EtcdCluster
#
require Logger

defmodule OpenAperture.WorkflowOrchestrator.Deployer.EtcdClusterMessagingResolver do
	use GenServer

  @moduledoc """
  This module contains the logic to resolve the correct MessagingExchange for an EtcdCluster
  """

  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.EtcdCluster

  @doc """
  Specific start_link implementation (required by the supervisor)

  ## Options

  ## Return Values

  {:ok, pid} | {:error, reason}
  """
  @spec start_link() :: {:ok, pid} | {:error, String.t}
  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Method to retrieve the identifier for the MessagingExchange associated with an EtcdCluster

  ## Options

  The `etcd_token` option defines token for the EtcdCluster

  ## Return Values

  messaging_exchange_id
  """
  @spec exchange_for_cluster(String.t) :: String.t
  def exchange_for_cluster(etcd_token) do
  	GenServer.call(__MODULE__, {:exchange_for_cluster, etcd_token})
  end

  @doc """
  Call handler to retrieve the identifier for the MessagingExchange associated with an EtcdCluster

  ## Options

  The `etcd_token` option defines token for the EtcdCluster

  The `_from` option defines the tuple {from, ref}

  The `state` option represents the server's current state

  ## Return Values

  {:reply, {messaging_exchange_id, machine}, resolved_state}
  """
  @spec handle_call({:exchange_for_cluster, String.t}, term, map) :: {:reply, {String.t, map}, map}
  def handle_call({:exchange_for_cluster, etcd_token}, _from, state) do
    {:reply, get_exchange_for_cluster(etcd_token), state}
  end

  @doc """
  Method to retrieve the messaging_exchange_id for an etcd_token

  ## Options

  The `etcd_token` option defines token for the EtcdCluster

  ## Return Values

  List of {messaging_exchange_id, cluster}
  """
  @spec get_exchange_for_cluster(map) :: list
  def get_exchange_for_cluster(etcd_token) do
    case EtcdCluster.get_cluster!(ManagerApi.get_api, etcd_token) do
      nil -> nil
      cluster -> cluster["messaging_exchange_id"]
    end
  end
end
