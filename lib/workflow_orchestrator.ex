#
# == workflow_orchestrator.ex
#
# This module contains definition the OpenAperture Workflow Orchestrator implementation
#
require Logger
defmodule OpenAperture.WorkflowOrchestrator do
	use Application

  @moduledoc """
  This module contains definition the OpenAperture WorkflowOrchestrator implementation
  """

  @doc """
  Starts the given `_type`.

  If the `_type` is not loaded, the application will first be loaded using `load/1`.
  Any included application, defined in the `:included_applications` key of the
  `.app` file will also be loaded, but they won't be started.

  Furthermore, all applications listed in the `:applications` key must be explicitly
  started before this application is. If not, `{:error, {:not_started, app}}` is
  returned, where `_type` is the name of the missing application.

  In case you want to automatically  load **and start** all of `_type`'s dependencies,
  see `ensure_all_started/2`.

  The `type` argument specifies the type of the application:

    * `:permanent` - if `_type` terminates, all other applications and the entire
      node are also terminated.

    * `:transient` - if `_type` terminates with `:normal` reason, it is reported
      but no other applications are terminated. If a transient application
      terminates abnormally, all other applications and the entire node are
      also terminated.

    * `:temporary` - if `_type` terminates, it is reported but no other
      applications are terminated (the default).

  Note that it is always possible to stop an application explicitly by calling
  `stop/1`. Regardless of the type of the application, no other applications will
  be affected.

  Note also that the `:transient` type is of little practical use, since when a
  supervision tree terminates, the reason is set to `:shutdown`, not `:normal`.
  """
  @spec start(atom, [any]) :: :ok | {:error, String.t}
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    Logger.info("Starting OpenAperture.WorkflowOrchestrator...")
    children = [
      # Define workers and child supervisors to be supervised
      supervisor(OpenAperture.WorkflowOrchestrator.Supervisor, [])
    ]

    opts = [strategy: :one_for_one, name: __MODULE__]
    Supervisor.start_link(children, opts)
  end
end
