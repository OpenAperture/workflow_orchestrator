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
      {:ex_doc, "0.8.4", only: :test},
      {:earmark, "0.1.17", only: :test},
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "380ce611a038dd8f7afb4fa7f660aeac06475af0", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "dc06f0a484410e7707dab8e96807d54a564557ed", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "67e1ec93cf1e12e5b0e86165f33ede703a886092", override: true},

      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "9fa880eef5aa23bf89e3f121df04fdc542c74c73", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "86e32dc7574499e84add246a48d35b1f98344798", override: true},
      
      {:timex_extensions, git: "https://github.com/OpenAperture/timex_extensions.git", ref: "bf6fe4b5a6bd7615fc39877f64b31e285b7cc3de", override: true},

      {:timex, "~> 0.13.3", override: true},
      {:fleet_api, "~> 0.0.15", override: true},
      {:poison, "~>1.4.0", override: true},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", override: true},
      {:meck, "0.8.3", override: true}
    ]
  end
end
