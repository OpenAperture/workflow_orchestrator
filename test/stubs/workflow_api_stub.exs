defmodule OpenAperture.WorkflowOrchestrator.WorkflowAPIStub do
  @lists %{
    pending: [
      %{
        "id" => "1", "development_repo" => "myCloud/myApp",
        "workflow_completed" => false, "current_step" => "configure",
        "inserted_at" => "Thu, 30 Jul 2015 07:33:44 UTC"
      },
      %{
        "id" => "2", "development_repo" => "myCloud/myApp",
        "workflow_completed" => false, "current_step" => "configure",
        "inserted_at" => "Thu, 30 Jul 2015 07:33:45 UTC"
      }
    ],
    build: [
      %{
        "id" => "1", "development_repo" => "myCloud/myApp",
        "workflow_completed" => false, "current_step" => "configure",
        "inserted_at" => "Thu, 30 Jul 2015 07:33:44 UTC"
      },
      %{
        "id" => "2", "development_repo" => "myCloud/myApp",
        "workflow_completed" => false, "current_step" => "build",
        "inserted_at" => "Thu, 30 Jul 2015 07:13:45 UTC"
      }
    ]
  }

  def start(type) do
    Agent.start_link fn -> @lists[type] end
  end

  def list(agent) do
    Agent.get(agent, &(&1))
  end

  def reduce_no_of_entries(agent) do
    workflows = list(agent)

    if workflows != [] do
      in_build = workflows |> Enum.find fn(wf) ->
        wf["current_step"] == "build"
      end

      rest = if in_build do
        workflows |> Enum.reject &(&1["current_step"] == "build")
      else
        tl(workflows)
      end

      Agent.update(agent, fn _data -> rest end)
    end

    :ok
  end
end
