# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for third-
# party users, it should be done in your mix.exs file.

# Sample configuration:
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]

config :autostart,
	register_queues: false

config :openaperture_manager_api, 
	manager_url: "https://openaperture-mgr.host.co",
	oauth_login_url: "https://auth.host.co",
	oauth_client_id: "id",
	oauth_client_secret: "secret"

config :openaperture_workflow_orchestrator, 
	exchange_id: "1",
	broker_id: "1",
	sleep_delay_factor: 0

config :openaperture_overseer_api,
	module_type: :test,
	autostart: false,	
	exchange_id: "1",
	broker_id: "1"