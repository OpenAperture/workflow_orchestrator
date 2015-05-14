defmodule OpenAperture.WorkflowOrchestrator.WorkflowFSMTest do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Httpc, options: [clear_mock: true]

  alias OpenAperture.WorkflowOrchestrator.Workflow
  alias OpenAperture.WorkflowOrchestrator.WorkflowFSM

  alias OpenAperture.WorkflowOrchestrator.Dispatcher

  alias OpenAperture.WorkflowOrchestrator.Builder.DockerHostResolver
  alias OpenAperture.WorkflowOrchestrator.Builder.Publisher, as: BuilderPublisher
  alias OpenAperture.WorkflowOrchestrator.Deployer.Publisher, as: DeployerPublisher
  alias OpenAperture.WorkflowOrchestrator.Deployer.EtcdClusterMessagingResolver

  # ============================
  # start_link tests

  test "start_link - success" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
  	:meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
  	
  	payload = %{
  	}

    {result, fsm} = WorkflowFSM.start_link(payload, "#{UUID.uuid1()}")
    assert result == :ok
    assert fsm != nil
  after
  	:meck.unload(Workflow)   
  end

  test "start_link - failure" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> {:error, "bad news bears"} end)
  	
  	payload = %{
  	}

    {result, reason} = WorkflowFSM.start_link(payload, "#{UUID.uuid1()}")
    assert result == :error
    assert reason == "bad news bears"
  after
  	:meck.unload(Workflow)   
  end

  # ============================
  # workflow_starting tests

  test "workflow_starting - completed" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
  	:meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
  	
  	payload = %{
  	}

    {:ok, workflow} = WorkflowFSM.start_link(payload, "#{UUID.uuid1()}")
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
  	:meck.unload(Workflow)    
  end

  test "workflow_starting - completed without any milestones" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
  	:meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :complete?, fn _ -> true end)
  	:meck.expect(Workflow, :resolve_next_milestone, fn _ -> :workflow_completed end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
  	  	
  	payload = %{
  	}

    {:ok, workflow} = WorkflowFSM.start_link(payload, "#{UUID.uuid1()}")
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
  	:meck.unload(Workflow)    
  end  

  # ============================
  # terminate tests

  test "terminate" do
    assert WorkflowFSM.terminate(:normal, :workflow_completed, %{workflow_fsm_prefix: "[]"}) == :ok   
  end

  # ============================
  # workflow_completed tests

  test "workflow_completed - success" do
		assert WorkflowFSM.workflow_completed(:workflow_completed, nil, %{workflow: %{}}) == {:stop, :normal, {:completed, %{}}, %{workflow: %{}}}
  end

  test "workflow_completed - completed without any milestones through FSM" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
  	:meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
  	
  	payload = %{
  	}

    {:ok, workflow} = WorkflowFSM.start_link(payload, "#{UUID.uuid1()}")
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
  	:meck.unload(Workflow)  
  end

  # ============================
  # build tests

  test "build - resolution failed" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :workflow_failed, fn _, _ -> :ok end)
    :meck.expect(Workflow, :failed?, fn _ -> true end)

  	:meck.new(DockerHostResolver, [:passthrough])
  	:meck.expect(DockerHostResolver, :next_available, fn -> {nil, nil} end)  	

  	:meck.new(Dispatcher, [:passthrough])
  	:meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)  	

  	state_data = %{workflow_fsm_prefix: "[]", workflow: %{}}
		assert WorkflowFSM.build(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
  	:meck.unload(Workflow)
  	:meck.unload(DockerHostResolver)
  	:meck.unload(Dispatcher)
  end

  test "build - success" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)

  	state_data = %{workflow_fsm_prefix: "[]", workflow: %{}, delivery_tag: "#{UUID.uuid1()}"}
  	:meck.new(BuilderPublisher, [:passthrough])
  	:meck.expect(BuilderPublisher, :build, fn delivery_tag, messaging_exchange_id, payload -> 
  		assert delivery_tag == state_data[:delivery_tag]

  		assert messaging_exchange_id == 123

  		assert payload != nil
  		assert payload[:docker_build_etcd_token] == "123456789000"
  		assert payload[:notifications_exchange_id] == "1"
  		assert payload[:notifications_broker_id] == "1"
  		assert payload[:workflow_orchestration_exchange_id] == "1"
  		assert payload[:workflow_orchestration_broker_id] == "1"
      assert payload[:orchestration_queue_name] == "workflow_orchestration"
  		:ok 
  	end)

  	:meck.new(DockerHostResolver, [:passthrough])
  	:meck.expect(DockerHostResolver, :next_available, fn -> {123, %{"etcd_token" => "123456789000"}} end)
  	
		assert WorkflowFSM.build(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
  	:meck.unload(Workflow) 
  	:meck.unload(DockerHostResolver)	
  	:meck.unload(BuilderPublisher)
  end

  test "build - success through FSM" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
  	:meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :complete?, fn _ -> false end)
  	:meck.expect(Workflow, :get_info, fn _ -> %{} end)
  	:meck.expect(Workflow, :resolve_next_milestone, fn _ -> :build end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)

  	orig_delivery_tag = "#{UUID.uuid1()}"
  	:meck.new(BuilderPublisher, [:passthrough])
  	:meck.expect(BuilderPublisher, :build, fn delivery_tag, messaging_exchange_id, payload -> 
  		assert delivery_tag == orig_delivery_tag

  		assert messaging_exchange_id == 123

  		assert payload != nil
  		assert payload[:docker_build_etcd_token] == "123456789000"
  		assert payload[:notifications_exchange_id] == "1"
  		assert payload[:notifications_broker_id] == "1"
      assert payload[:workflow_orchestration_exchange_id] == "1"
      assert payload[:workflow_orchestration_broker_id] == "1"
      assert payload[:orchestration_queue_name] == "workflow_orchestration"
  		:ok 
  	end)

  	:meck.new(DockerHostResolver, [:passthrough])
  	:meck.expect(DockerHostResolver, :next_available, fn -> {123, %{"etcd_token" => "123456789000"}} end)
  	
  	payload = %{
  	}
  	
    {:ok, workflow} = WorkflowFSM.start_link(payload, orig_delivery_tag)
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
  	:meck.unload(Workflow) 
  	:meck.unload(BuilderPublisher) 
  	:meck.unload(DockerHostResolver)
  end
 

  # ============================
  # deploy tests

  test "deploy - resolution failed" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :workflow_failed, fn _, _ -> :ok end)
  	:meck.expect(Workflow, :get_info, fn _ -> %{} end)

  	:meck.new(EtcdClusterMessagingResolver, [:passthrough])
  	:meck.expect(EtcdClusterMessagingResolver, :exchange_for_cluster, fn _ -> nil end)

  	:meck.new(Dispatcher, [:passthrough])
  	:meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)  	

  	state_data = %{workflow_fsm_prefix: "[]", workflow: %{}}
		assert WorkflowFSM.deploy(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
  	:meck.unload(Workflow)
  	:meck.unload(EtcdClusterMessagingResolver)
  	:meck.unload(Dispatcher)
  end

  test "deploy - success" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)

  	state_data = %{workflow_fsm_prefix: "[]", workflow: %{}, delivery_tag: "#{UUID.uuid1()}"}
  	:meck.new(DeployerPublisher, [:passthrough])
  	:meck.expect(DeployerPublisher, :deploy, fn delivery_tag, messaging_exchange_id, payload -> 
  		assert delivery_tag == state_data[:delivery_tag]

  		assert messaging_exchange_id == 123

  		assert payload != nil
  		assert payload[:notifications_exchange_id] == "1"
  		assert payload[:notifications_broker_id] == "1"
      assert payload[:workflow_orchestration_exchange_id] == "1"
      assert payload[:workflow_orchestration_broker_id] == "1"
      assert payload[:orchestration_queue_name] == "workflow_orchestration"
  		:ok 
  	end)

  	:meck.new(EtcdClusterMessagingResolver, [:passthrough])
  	:meck.expect(EtcdClusterMessagingResolver, :exchange_for_cluster, fn _ -> 123 end)
  	
		assert WorkflowFSM.deploy(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
  	:meck.unload(Workflow) 
  	:meck.unload(EtcdClusterMessagingResolver)	
  	:meck.unload(DeployerPublisher)
  end

  test "deploy - success through FSM" do
  	:meck.new(Workflow, [:passthrough])
  	:meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
  	:meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
  	:meck.expect(Workflow, :save, fn _ -> :ok end)
  	:meck.expect(Workflow, :complete?, fn _ -> true end)
  	:meck.expect(Workflow, :get_info, fn _ -> %{} end)
  	:meck.expect(Workflow, :resolve_next_milestone, fn _ -> :deploy end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)

  	orig_delivery_tag = "#{UUID.uuid1()}"
  	:meck.new(DeployerPublisher, [:passthrough])
  	:meck.expect(DeployerPublisher, :deploy, fn delivery_tag, messaging_exchange_id, payload -> 
  		assert delivery_tag == orig_delivery_tag

  		assert messaging_exchange_id == 123

  		assert payload != nil
  		assert payload[:notifications_exchange_id] == "1"
  		assert payload[:notifications_broker_id] == "1"
      assert payload[:workflow_orchestration_exchange_id] == "1"
      assert payload[:workflow_orchestration_broker_id] == "1"
      assert payload[:orchestration_queue_name] == "workflow_orchestration"
  		:ok 
  	end)

  	:meck.new(EtcdClusterMessagingResolver, [:passthrough])
  	:meck.expect(EtcdClusterMessagingResolver, :exchange_for_cluster, fn _ -> 123 end)
  	
  	payload = %{
  	}

    {:ok, workflow} = WorkflowFSM.start_link(payload, orig_delivery_tag)
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
  	:meck.unload(Workflow)  
  	:meck.unload(EtcdClusterMessagingResolver)
  	:meck.unload(DeployerPublisher)
  end
end
