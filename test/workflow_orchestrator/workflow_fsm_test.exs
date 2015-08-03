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
  alias OpenAperture.WorkflowOrchestrator.WorkflowAPIStub

  # ============================
  # start_link tests

  setup_all do
    Code.require_file("test/stubs/workflow_api_stub.exs")
    :ok
  end

  test "start_link - success" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)

    payload = %{}

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
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

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
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    payload = %{
    }

    {:ok, workflow} = WorkflowFSM.start_link(payload, "#{UUID.uuid1()}")
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
    :meck.unload(Workflow)
  end

  test "workflow_starting - test email notification" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :failed?, fn _ -> true end)
    :meck.expect(Workflow, :workflow_failed, fn _,_ -> true end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    payload = %{
    }

    {:reply, :in_progress, :workflow_completed, state_data} = WorkflowFSM.workflow_starting(%{}, %{}, %{workflow: payload})
    assert state_data != nil
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
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    assert WorkflowFSM.workflow_completed(:workflow_completed, nil, %{workflow: %{}}) == {:stop, :normal, {:completed, %{}}, %{workflow: %{}}}
  after
    :meck.unload(Workflow)
  end

  test "workflow_completed - completed without any milestones through FSM" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

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
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)

    :meck.new(DockerHostResolver, [:passthrough])
    :meck.expect(DockerHostResolver, :next_available, fn -> {nil, nil} end)

    :meck.new(Dispatcher, [:passthrough])
    :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:pending)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{deployment_repo: "myCloud/myApp"}}
    assert WorkflowFSM.build(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
    :meck.unload(Workflow)
    :meck.unload(DockerHostResolver)
    :meck.unload(Dispatcher)
  end

  test "build - no builders available" do
    {:ok, pid} = Agent.start_link(fn -> false end);
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :workflow_failed, fn _, msg ->
                          assert msg == "Unable to request build - no Builders are currently accessible in exchange 123!"
                          Agent.update(pid, fn _ -> true end)
                          :ok
                        end)
    :meck.expect(Workflow, :failed?, fn _ -> true end)

    :meck.expect(Workflow, :get_info, fn _ -> %{current_step: "build"} end)

    :meck.new(DockerHostResolver, [:passthrough])
    :meck.expect(DockerHostResolver, :next_available, fn -> {123, %{"etcd_token" => "123456789000"}} end)

    :meck.new(Dispatcher, [:passthrough])
    :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)

    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> false end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:build)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{deployment_repo: "myCloud/myApp"}}
    assert WorkflowFSM.build(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
    assert Agent.get(pid, &(&1))
  after
    :meck.unload(Workflow)
    :meck.unload(DockerHostResolver)
    :meck.unload(Dispatcher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "build - success" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:build)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{deployment_repo: "myCloud/myApp"}, delivery_tag: "#{UUID.uuid1()}"}
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
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "build - success, override messaging_exchange_id" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{build_messaging_exchange_id: 789} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:pending)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{deployment_repo: "myCloud/myApp"}, delivery_tag: "#{UUID.uuid1()}"}
    :meck.new(BuilderPublisher, [:passthrough])
    :meck.expect(BuilderPublisher, :build, fn delivery_tag, messaging_exchange_id, payload ->
      assert delivery_tag == state_data[:delivery_tag]

      assert messaging_exchange_id == 789

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
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "build - success through FSM" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn(_) ->
      %{
        deployment_repo: "myCloud/myApp",
        workflow_id: 42
      }
    end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> false end)
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :resolve_next_milestone, fn _ -> :build end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)


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

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:build)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)



    payload = %{}

    {:ok, workflow} = WorkflowFSM.start_link(payload, orig_delivery_tag)
    {result, workflow_info} = WorkflowFSM.execute(workflow)
    assert result == :completed
    assert workflow != nil
  after
    :meck.unload(Workflow)
    :meck.unload(BuilderPublisher)
    :meck.unload(DockerHostResolver)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "no queued builds" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn _ ->
      %{deployment_repo: "Cloud/MyApp_docker"}
    end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> false end)
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :resolve_next_milestone, fn _ -> :build end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)


    orig_delivery_tag = "#{UUID.uuid1()}"
    :meck.new(BuilderPublisher, [:passthrough])
    :meck.expect(BuilderPublisher, :build, fn delivery_tag, messaging_exchange_id, payload -> end)

    :meck.new(DockerHostResolver, [:passthrough])
    :meck.expect(DockerHostResolver, :next_available, fn -> {123, %{"etcd_token" => "123456789000"}} end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) -> [] end)

    payload = %{}

    {:ok, workflow} = WorkflowFSM.start_link(payload, orig_delivery_tag)
    {result, workflow_info} = WorkflowFSM.execute(workflow)

    assert result == :completed
    assert workflow != nil
  after
    :meck.unload(Workflow)
    :meck.unload(BuilderPublisher)
    :meck.unload(DockerHostResolver)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "only pending builds queued up" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn(_) ->
      %{
        deployment_repo: "myCloud/myApp",
        workflow_id: 42
      }
    end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> false end)
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :resolve_next_milestone, fn _ -> :build end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)


    orig_delivery_tag = "#{UUID.uuid1()}"
    :meck.new(BuilderPublisher, [:passthrough])
    :meck.expect(BuilderPublisher, :build, fn delivery_tag, messaging_exchange_id, payload -> end)

    :meck.new(DockerHostResolver, [:passthrough])
    :meck.expect(DockerHostResolver, :next_available, fn -> {123, %{"etcd_token" => "123456789000"}} end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:pending)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    payload = %{}

    {:ok, workflow} = WorkflowFSM.start_link(payload, orig_delivery_tag)
    {result, workflow_info} = WorkflowFSM.execute(workflow)

    assert result == :completed
    assert workflow != nil
  after
    :meck.unload(Workflow)
    :meck.unload(BuilderPublisher)
    :meck.unload(DockerHostResolver)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "both a build in progress and a pending build" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn(_) ->
      %{
        deployment_repo: "myCloud/myApp",
        workflow_id: 42
      }
    end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> false end)
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :resolve_next_milestone, fn _ -> :build end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    orig_delivery_tag = "#{UUID.uuid1()}"
    :meck.new(BuilderPublisher, [:passthrough])
    :meck.expect(BuilderPublisher, :build, fn delivery_tag, messaging_exchange_id, payload -> end)

    :meck.new(DockerHostResolver, [:passthrough])
    :meck.expect(DockerHostResolver, :next_available, fn -> {123, %{"etcd_token" => "123456789000"}} end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:build)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    payload = %{}

    {:ok, workflow} = WorkflowFSM.start_link(payload, orig_delivery_tag)
    {result, workflow_info} = WorkflowFSM.execute(workflow)

    assert result == :completed
    assert workflow != nil
  after
    :meck.unload(Workflow)
    :meck.unload(BuilderPublisher)
    :meck.unload(DockerHostResolver)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
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

  test "deploy - no deployers" do
    {:ok, pid} = Agent.start_link(fn -> false end);
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :workflow_failed, fn _, msg ->
                          assert msg == "Unable to request deploy - no deploy clusters are available in exchange 123!"
                          Agent.update(pid, fn _ -> true end)
                          :ok
                        end)
    :meck.expect(Workflow, :get_info, fn _ -> %{etcd_token: "123abc"} end)

    :meck.new(EtcdClusterMessagingResolver, [:passthrough])
    :meck.expect(EtcdClusterMessagingResolver, :exchange_for_cluster, fn _ -> 123 end)

    :meck.new(Dispatcher, [:passthrough])
    :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> false end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}}
    assert WorkflowFSM.deploy(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
    assert Agent.get(pid, &(&1))
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(Dispatcher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "deploy - failed - no etcd_token" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{} end)
    :meck.expect(Workflow, :workflow_failed, fn _,_ -> :ok end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

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

  test "deploy - success" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{etcd_token: "123abc", current_step: :deploy} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)

    :meck.new(OpenAperture.ManagerApi.Workflow)
    {:ok, wfapi_stub} = WorkflowAPIStub.start(:build)
    :meck.expect(OpenAperture.ManagerApi.Workflow, :list!, fn(_, _) ->
      list = WorkflowAPIStub.list(wfapi_stub)
      WorkflowAPIStub.reduce_no_of_entries(wfapi_stub)
      list
    end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{deployment_repo: "myCloud/myApp"}, delivery_tag: "#{UUID.uuid1()}"}
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
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    assert WorkflowFSM.deploy(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(DeployerPublisher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "deploy - success, override messaging_exchange_id" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{deploy_messaging_exchange_id: 789, etcd_token: "123abc", current_step: :deploy} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}, delivery_tag: "#{UUID.uuid1()}"}
    :meck.new(DeployerPublisher, [:passthrough])
    :meck.expect(DeployerPublisher, :deploy, fn delivery_tag, messaging_exchange_id, payload ->
      assert delivery_tag == state_data[:delivery_tag]

      assert messaging_exchange_id == 789

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
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    assert WorkflowFSM.deploy(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(DeployerPublisher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "deploy - success through FSM" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :get_info, fn _ -> %{current_step: :deploy} end)
    :meck.expect(Workflow, :resolve_next_milestone, fn _ -> :deploy end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

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

  # ============================
  # deploy_oa tests

  test "deploy_oa - resolution failed" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :workflow_failed, fn _, _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{current_step: :deploy_oa} end)

    :meck.new(EtcdClusterMessagingResolver, [:passthrough])
    :meck.expect(EtcdClusterMessagingResolver, :exchange_for_cluster, fn _ -> nil end)

    :meck.new(Dispatcher, [:passthrough])
    :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}}
    assert WorkflowFSM.deploy_oa(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(Dispatcher)
  end

  test "deploy_oa - no deployers" do
    {:ok, pid} = Agent.start_link(fn -> false end);
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :workflow_failed, fn _, msg ->
                          assert msg == "Unable to request deploy - no deploy clusters are available in exchange 123!"
                          Agent.update(pid, fn _ -> true end)
                          :ok
                        end)
    :meck.expect(Workflow, :get_info, fn _ -> %{etcd_token: "123abc", current_step: :deploy_oa} end)

    :meck.new(EtcdClusterMessagingResolver, [:passthrough])
    :meck.expect(EtcdClusterMessagingResolver, :exchange_for_cluster, fn _ -> 123 end)

    :meck.new(Dispatcher, [:passthrough])
    :meck.expect(Dispatcher, :acknowledge, fn _ -> :ok end)
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> false end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}}
    assert WorkflowFSM.deploy_oa(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
    assert Agent.get(pid, &(&1))
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(Dispatcher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "deploy_oa - failed - no etcd_token" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{current_step: :deploy_oa} end)
    :meck.expect(Workflow, :workflow_failed, fn _,_ -> :ok end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}, delivery_tag: "#{UUID.uuid1()}"}
    :meck.new(DeployerPublisher, [:passthrough])
    :meck.expect(DeployerPublisher, :deploy_oa, fn delivery_tag, messaging_exchange_id, payload ->
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

    assert WorkflowFSM.deploy_oa(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(DeployerPublisher)
  end

  test "deploy_oa - success" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{etcd_token: "123abc", current_step: :deploy_oa} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}, delivery_tag: "#{UUID.uuid1()}"}
    :meck.new(DeployerPublisher, [:passthrough])
    :meck.expect(DeployerPublisher, :deploy_oa, fn delivery_tag, messaging_exchange_id, payload ->
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
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(DeployerPublisher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "deploy_oa - success, override messaging_exchange_id" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :get_info, fn _ -> %{deploy_messaging_exchange_id: 789, etcd_token: "123abc", current_step: :deploy_oa} end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :add_success_notification, fn _,_ -> :ok end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    state_data = %{workflow_fsm_prefix: "[]", workflow: %{}, delivery_tag: "#{UUID.uuid1()}"}
    :meck.new(DeployerPublisher, [:passthrough])
    :meck.expect(DeployerPublisher, :deploy_oa, fn delivery_tag, messaging_exchange_id, payload ->
      assert delivery_tag == state_data[:delivery_tag]

      assert messaging_exchange_id == 789

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
    :meck.new(OpenAperture.ManagerApi.MessagingExchange, [:passthrough])
    :meck.expect(OpenAperture.ManagerApi.MessagingExchange, :exchange_has_modules_of_type?, fn _, _ -> true end)

    assert WorkflowFSM.deploy_oa(:workflow_completed, nil, state_data) == {:reply, :in_progress, :workflow_completed, state_data}
  after
    :meck.unload(Workflow)
    :meck.unload(EtcdClusterMessagingResolver)
    :meck.unload(DeployerPublisher)
    :meck.unload(OpenAperture.ManagerApi.MessagingExchange)
  end

  test "deploy_oa - success through FSM" do
    :meck.new(Workflow, [:passthrough])
    :meck.expect(Workflow, :create_from_payload, fn _ -> %{} end)
    :meck.expect(Workflow, :get_id, fn _ -> "123abc" end)
    :meck.expect(Workflow, :save, fn _ -> :ok end)
    :meck.expect(Workflow, :complete?, fn _ -> true end)
    :meck.expect(Workflow, :get_info, fn _ -> %{current_step: :deploy_oa} end)
    :meck.expect(Workflow, :resolve_next_milestone, fn _ -> :deploy_oa end)
    :meck.expect(Workflow, :failed?, fn _ -> false end)
    :meck.expect(Workflow, :send_workflow_completed_email, fn _ -> :ok end)

    orig_delivery_tag = "#{UUID.uuid1()}"
    :meck.new(DeployerPublisher, [:passthrough])
    :meck.expect(DeployerPublisher, :deploy_oa, fn delivery_tag, messaging_exchange_id, payload ->
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

    payload = %{}

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
