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

config :cloudos_manager_api, 
	manager_url: System.get_env("CLOUDOS_MANAGER_URL") || "https://cloudos-mgr.host.co",
	oauth_login_url: System.get_env("CLOUDOS_OAUTH_LOGIN_URL") || "https://auth.host.co",
	client_id: System.get_env("CLOUDOS_OAUTH_CLIENT_ID") ||"id",
	client_secret: System.get_env("CLOUDOS_OAUTH_CLIENT_SECRET") || "secret"

config :cloudos_workflow_orchestrator, 
	exchange_id: "1",
	broker_id: "1"