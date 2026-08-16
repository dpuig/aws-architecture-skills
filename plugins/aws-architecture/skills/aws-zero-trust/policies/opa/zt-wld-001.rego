# ZT-WLD-001 — AWS-hosted workloads use instance or task roles.
#
# AWS delivers temporary credentials to the compute resource directly, so a
# static key in an environment block on AWS-hosted compute is never a technical
# necessity — and it has no expiry.
package main

import rego.v1

credential_keys := {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"}

# Lambda environment variables.
deny contains msg if {
	some fn in of_type("aws_lambda_function")
	some env in fn.change.after.environment
	some k, _ in env.variables
	k in credential_keys
	msg := sprintf(
		"ZT-WLD-001: %s sets %s in its environment. Use the Lambda execution role; the SDK discovers those credentials automatically.",
		[fn.address, k],
	)
}

# ECS container definitions are a JSON string.
deny contains msg if {
	some td in of_type("aws_ecs_task_definition")
	defs := json.unmarshal(td.change.after.container_definitions)
	some container in defs
	some env in container.environment
	env.name in credential_keys
	msg := sprintf(
		"ZT-WLD-001: %s sets %s in container '%s'. Use the ECS task role instead.",
		[td.address, env.name, container.name],
	)
}
