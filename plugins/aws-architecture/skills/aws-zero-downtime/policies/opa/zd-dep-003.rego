# ZD-DEP-003 — Infrastructure is immutable.
#
# In-place mutation produces hosts whose state is the sum of every change ever
# applied, in order, with failures. Replacement produces hosts whose state is a
# function of the artifact alone — which is what makes rollback mean anything.
package main

import rego.v1

# Launch configurations cannot be versioned, so a fleet using one has no
# artifact to roll back to.
deny contains msg if {
	some lc in of_type("aws_launch_configuration")
	msg := sprintf(
		"ZD-DEP-003: %s is a launch configuration, which cannot be versioned. Use aws_launch_template so a rollback has a prior version to return to.",
		[lc.address],
	)
}

# An ASG referencing a launch template by a moving alias re-resolves on every
# scale-out, so two instances in the same group can run different images.
deny contains msg if {
	some asg in of_type("aws_autoscaling_group")
	some lt in asg.change.after.launch_template
	lt.version == "$Latest"
	msg := sprintf(
		"ZD-DEP-003: %s pins launch_template version to $Latest, so scale-out silently changes the running image. Pin an explicit version and change it through the pipeline.",
		[asg.address],
	)
}

# :latest has the same problem for containers.
deny contains msg if {
	some td in of_type("aws_ecs_task_definition")
	defs := json.unmarshal(td.change.after.container_definitions)
	some container in defs
	endswith(container.image, ":latest")
	msg := sprintf(
		"ZD-DEP-003: %s container '%s' uses image tag ':latest'. Pin an immutable digest or version tag so a task restart cannot change the running code.",
		[td.address, container.name],
	)
}
