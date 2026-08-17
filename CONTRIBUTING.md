# Contributing

Control records are not ordinary code. They appear in customer-facing output and
are meant to survive a security review, so the rules below are stricter than a
typical repository's.

Read [VERIFICATION.md](VERIFICATION.md) first — it is the current honest account
of what is checked and what is not, and most useful contributions are listed
there as gaps.

## Non-negotiables

**Control IDs are immutable.** Never renumber, never reuse. A superseded control
is marked, not deleted. IDs appear in generated deliverables and in
`validate.sh` — five ZD IDs are hard-coded there, and renumbering one breaks the
validator without producing an error.

**`satisfied` requires evidence.** A control with no executable check can only
ever be `recommended`. Do not add a code path that reports `satisfied` on
intent, plan-time reasoning, or a check that did not run.

**Never add a PASS branch to a stage that does not verify anything.** Stage 5
previously reported PASS while doing nothing at all. If a check is not
implemented, it reports `skipped` and blocks the gate.

**Every control cites an `authority`.** For `tier: required`, that source must
carry the **N** marker in the source register and must not be `unverified`.

## Adding a control

1. Read the actual source page. Not the section index that names it — the page
   itself. Roughly half this catalog is currently anchored on pages that were
   never opened, and that is the single largest quality debt here. Do not add to
   it.
2. Register the source in
   `plugins/aws-architecture/skills/aws-solution-architect/references/kb-sources.md` with a `Verified`
   date if it is not already there.
3. Conform to
   `plugins/aws-architecture/skills/aws-solution-architect/references/control-record-schema.md`.
4. Take the next free ID in the domain. Do not renumber to close gaps —
   reserved-but-unauthored IDs (`ZT-NET-011`) stay reserved.
5. Add the control to its domain file **and** the domain's
   `control-catalog.md` index, including the cross-domain dependency table if it
   names another control.
6. If `exceptions[].requires` names a control, that control must exist.

## Adding a policy

**A policy without a test that proves it fires will not be merged.**

Two policies in this repository shipped in a compiling-but-never-firing state.
One read a value that Terraform places in `after_unknown` at plan time; the
other relied on `not x`, which does not match an explicit JSON `null` because
Rego treats null as truthy. Both compiled. Both reported clean. Both were
counted as coverage.

So:

1. Name the file for the control: `policies/opa/zt-net-014.rego`.
2. **Start the deny message with the control ID.** `validate.sh` extracts the
   first ID it finds in the message; a message that mentions another control
   before its own will be misattributed.
3. Add a resource to `tests/fixtures/violating/main.tf` that triggers it.
4. Add an assertion to `tests/run.sh`.
5. If the policy has more than one deny rule, **assert each rule separately.**
   Asserting only the control ID hides a regression in every rule but the first.
6. Run the suite. Confirm it fails when your fixture resource is removed.

### Plan-time hazards

- Values referencing another resource's computed attribute land in
  `after_unknown`, not `after`.
- JSON `null` is truthy in Rego. Use an explicit `object.get(obj, key, null) == null`.
- Prefer `resource_changes` (flat) over `planned_values` (nested) so module
  nesting cannot hide a resource.

## Licensing of contributions

Contributions are accepted under Apache-2.0.

**Do not paste third-party text into control prose.** Control records are
original writing that cites sources. In particular:

- CIS Benchmark text is redistribution-restricted — cite version and control
  number only.
- AWS documentation is copyrighted — paraphrase and cite; do not reproduce.
- NIST material is public domain and may be quoted.

The `rationale` field is where copying creeps in during extraction. Watch it in
review.

## Test the whole thing before opening a PR

```sh
plugins/aws-architecture/scripts/preflight.sh
for s in plugins/aws-architecture/skills/*/tests/run.sh; do bash "$s" || exit 1; done
```

CI runs the same on every push and pull request.

### Clean up before installing the plugin locally

The suites run `terraform init` in every fixture directory, which leaves roughly
**3.8 GB** of provider binaries in the working tree. That is gitignored, so it
never reaches the repo — but `claude plugin install` from a directory source
copies the *directory*, not the git tree, and `.gitignore` does not apply. A
plugin cache that should be about 440 KB ends up in the gigabytes, once per
installed version.

Clean before installing:

```sh
find . -name .terraform -type d -prune -exec rm -rf {} +
find . \( -name tf.plan -o -name .terraform.lock.hcl \) -delete
find . -name __pycache__ -type d -prune -exec rm -rf {} +
```

The suites re-run `terraform init` themselves, so nothing is lost by deleting
it.
