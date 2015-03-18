defmodule CloudOS.WorkflowOrchestrator.Mixfile do
  use Mix.Project

  def project do
    [app: :cloudos_workflow_orchestrator,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      mod: { CloudOS.WorkflowOrchestrator, [] },
      applications: [:logger, :cloudos_messaging]
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
      {:json, "~> 0.3.2"},
      {:cloudos_messaging, git: "git@github.com:UmbrellaCorporation-SecretProjectLab/cloudos_messaging.git", ref: "890cd14c0d1e806595ab69bfc56bc9f9ea88a039"},
      {:timex_extensions, git: "git@github.com:UmbrellaCorporation-SecretProjectLab/timex_extensions.git", ref: "master"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", ref: "b418f02b3515e72185dc74d76741dc67787f539e", optional: true},
      {:meck, "0.8.2"}            
    ]
  end
end
