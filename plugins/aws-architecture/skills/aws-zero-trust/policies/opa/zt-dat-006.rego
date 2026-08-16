# ZT-DAT-006 — Encryption in transit is enforced.
#
# "Internal traffic is trusted" is the assumption Zero Trust exists to remove.
# A plaintext listener is permitted only when its sole action is a redirect to
# HTTPS — serving over HTTP is not the same as redirecting from it.
package main

import rego.v1

deny contains msg if {
	some listener in of_type("aws_lb_listener")
	upper(listener.change.after.protocol) == "HTTP"
	not redirects_to_https(listener)
	msg := sprintf(
		"ZT-DAT-006: %s serves plaintext HTTP. Terminate TLS, or make the listener's only action a redirect to HTTPS.",
		[listener.address],
	)
}

redirects_to_https(listener) if {
	some action in listener.change.after.default_action
	action.type == "redirect"
	some redirect in action.redirect
	upper(redirect.protocol) == "HTTPS"
}

# TLS listeners must not carry a legacy security policy.
deny contains msg if {
	some listener in of_type("aws_lb_listener")
	upper(listener.change.after.protocol) in {"HTTPS", "TLS"}
	policy := listener.change.after.ssl_policy
	contains(policy, "TLS-1-0")
	msg := sprintf(
		"ZT-DAT-006: %s uses ssl_policy %s, which permits TLS 1.0. Require TLS 1.2 or above.",
		[listener.address, policy],
	)
}
