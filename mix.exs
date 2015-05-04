defmodule OpenAperture.WorkflowOrchestrator.Mixfile do
  use Mix.Project

  def project do
    [app: :openaperture_workflow_orchestrator,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      mod: { OpenAperture.WorkflowOrchestrator, [] },
      applications: [
        :logger, 
        :openaperture_messaging, 
        :openaperture_manager_api,
        :openaperture_overseer_api,
        :openaperture_workflow_orchestrator_api
      ]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    [
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:test]},
      {:markdown, github: "devinus/markdown", only: [:test]},     

      {:poison, "~> 1.3.1"},
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "b313cf059816389288d946ae022b702e22a7fe68", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "ae629a4127acceac8a9791c85e5a0d3b67d1ad16", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "4d65d2295f2730bc74ec695c32fa0d2478158182", override: true},

      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "7aeca4655225fa0dd63f1465c0af30b0992b94b5", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "9f71efeda9ddf5315d3f7c945c5336347c720ac9", override: true},
      
      {:timex_extensions, git: "https://github.com/OpenAperture/timex_extensions.git", ref: "ab9d8820625171afbb80ccba1aa48feeb43dd790", override: true},

      {:timex, "~> 0.12.9"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", override: true},
      {:meck, "0.8.2", override: true}
    ]
  end
end
