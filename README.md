# OpenAperture.WorkflowOrchestrator

The WorkflowOrchestrator module provides a standardized mechanism to orchestrate Workflow events for builds and deploys and publish messages to the relevant consumers.  In order to successfully orchestrate messages, there are a few deployment-related assumptions:

* The Notifications module is running in the same exchange as the orchestrator
* The Builder module (wherever it's running) is has access to docker build clusters associated with it's exchange

## Module Responsibilities

The WorkflowOrchestrator module is responsible for the following actions within OpenAperture:

* Identify next Workflow step (via milestones), and publish request
* If “workflow_completed” flag is true, stop executing Workflow milestones.
* Save Workflow before executing request or completing Workflow
* Provide worker modules with Orchestraion and Notification callbacks.

## Messaging / Communication

The following message(s) may be sent to the WorkflowOrchestrator.  A Workflow is a OpenAperture construct that can be created/retrieved at /workflow.

* Start/Continue a Workflow
	* Queue:  workflow_orchestration
	* Payload (Map)
		* force_build 
		* db field:  workflow_id (same as id)
		* db field:  id
		* db field:  deployment_repo
		* db field:  deployment_repo_git_ref
		* db field:  source_repo 
		* db field:  source_repo_git_ref
		* db field:  milestones [:build, :deploy]
		* db field:  current_step 
		* db field:  elapsed_step_time 
		* db field:  elapsed_workflow_time
		* db field:  workflow_duration
		* db field:  workflow_step_durations
		* db field:  workflow_error 
		* db field:  workflow_completed
		* db field:  event_log
	* The following fields will be added to outgoing requests from the WorkflowOrchestrator
		* notifications_exchange_id
		* notifications_broker_id
		* orchestration_exchange_id
		* orchestration_broker_id
		* docker_build_etcd_token

## Module Configuration

The following configuration values must be defined either as environment variables or as part of the environment configuration files:

* Current Exchange
	* Type:  String
	* Description:  The identifier of the exchange in which the Orchestrator is running
  * Environment Variable:  EXCHANGE_ID
* Current Broker
	* Type:  String
	* Description:  The identifier of the broker to which the Orchestrator is connecting
  * Environment Variable:  BROKER_ID
* Manager URL
  * Type: String
  * Description: The url of the OpenAperture Manager
  * Environment Variable:  MANAGER_URL
  * Environment Configuration (.exs): :openaperture_manager_api, :manager_url
* OAuth Login URL
  * Type: String
  * Description: The login url of the OAuth2 server
  * Environment Variable:  OAUTH_LOGIN_URL
  * Environment Configuration (.exs): :openaperture_manager_api, :oauth_login_url
* OAuth Client ID
  * Type: String
  * Description: The OAuth2 client id to be used for authenticating with the OpenAperture Manager
  * Environment Variable:  OAUTH_CLIENT_ID
  * Environment Configuration (.exs): :openaperture_manager_api, :oauth_client_id
* OAuth Client Secret
  * Type: String
  * Description: The OAuth2 client secret to be used for authenticating with the OpenAperture Manager
  * Environment Variable:  OAUTH_CLIENT_SECRET
  * Environment Configuration (.exs): :openaperture_manager_api, :oauth_client_secret

## Building & Testing

### Building

The normal elixir project setup steps are required:

```iex
mix do deps.get, deps.compile
```

To startup the application, use mix run:

```iex
MIX_ENV=prod elixir --sname workflow_orchestrator -S mix run --no-halt
```

### Testing 

You can then run the tests

```iex
MIX_ENV=test mix test test/
```