# Architecture Diagrams

How the visual representation in deliverable §3 is produced. Workflow step 4b.

A diagram is the most persuasive artifact in an architecture deliverable and
historically the least verifiable. It gets screenshotted into slide decks, it
outlives the Terraform it described, and nobody diffs it. So the rule here is
the same one that governs control states:

> **The diagram is generated from the plan, not drawn from intent.**

A hand-drawn diagram is an unaudited claim about the architecture. A diagram
rendered from `plan.json` is evidence, and it cannot drift from what the
Terraform actually creates, because it is a projection of it.

---

## The renderer

```sh
scripts/render_diagram.py <plan.json> [--format mermaid|ascii|both] [--out DIR]
scripts/render_diagram.py <plan.json> --region-status
```

`validate.sh` runs it automatically at Stage 1b, writing `architecture.mmd` and
`architecture.txt` into the output directory. It reads the same `plan.json` that
Stages 2–4 assert against, so a control matrix and a diagram from the same run
describe the same infrastructure by construction.

Run it standalone only for inspection. In a deliverable, use the artifacts the
validated run produced — a diagram from a different plan than the one that was
validated is worse than no diagram.

## What it renders

Nesting expresses containment, which is also how trust boundaries and failure
domains are expressed:

```
Region  →  VPC  →  Availability Zone  →  subnet  →  resources
```

| Group | Meaning |
|---|---|
| `subnet … (private/public/tier unknown)` | Trust boundary. Tier comes from `map_public_ip_on_launch`; absent that signal it renders `tier unknown`, never assumed |
| AZ subgraphs | Failure domains — what §3 must name for the ZD-TOP controls to be auditable |
| `Spans AZs` | Resources with an explicit multi-AZ list, e.g. an ASG |
| `VPC-scoped` | In the VPC but not in any one subnet, e.g. a target group |
| `Regional / not VPC-bound` | No VPC or AZ linkage in the plan |
| `Placement unknown at plan time` | Declares a subnet/AZ/VPC whose value is not known until apply |

Non-containment references (`cluster`, `task_definition`, `launch_template`, …)
are drawn as labelled edges. Containment references are not — nesting already
shows them, and drawing both doubles every line for no added information.

## Honesty rules

These are not stylistic. They are the reason the diagram is allowed in a
deliverable that otherwise refuses unverified claims:

1. **Placement is read, never inferred.** A resource whose subnet is not
   resolvable from an explicit plan reference goes in *Placement unknown at plan
   time*. It is never dropped into a subnet to tidy the picture.
2. **Unknown values render as `?`.** Never a plausible substitute.
3. **A subnet's tier is never assumed.** `tier unknown` is a real output.
   Labelling a subnet "private" is a security claim, and a wrong one in a
   diagram will be believed for years.
4. **Empty is a valid rendering.** A subnet with nothing in it renders as
   declared-and-empty, visually distinct from an occupied one.
5. **Cross-module references that do not resolve are counted, not drawn.** An
   edge to a node that is not on the diagram is a line pointing at nothing.
6. **Every diagram carries its provenance footer** — resource count, unplaced
   count, unresolved reference count, and whether the Region is a placeholder.

## When the model may add to a diagram

Only *around* the generated one, never inside it. If the brief involves elements
that do not exist in the Terraform — an on-prem network, a third-party SaaS
consumer, an existing Transit Gateway the design attaches to — draw them in a
**separate** diagram, explicitly labelled:

```
Context diagram — NOT derived from plan.json. Hand-drawn from the brief.
```

Two labelled diagrams are honest. One merged diagram where the reader cannot
tell which boxes were verified and which were imagined is not, and it defeats
the entire point of generating the first one.

## Both formats, and why

| Format | File | Use |
|---|---|---|
| Mermaid | `architecture.mmd` | Renders in GitHub, docs sites, and the deliverable when the target supports it |
| ASCII | `architecture.txt` | Terminals, plain-text reports, diffs, and anywhere Mermaid does not render |

Emit **both** in §3. The ASCII version is the one that survives being pasted
into a ticket, and it diffs line-by-line between runs — which makes an
architecture change visible in review rather than requiring two images to be
compared by eye.

Mermaid labels avoid characters that break its parser (`"`, `[`, `]` are
substituted). Node IDs are sanitized and uniquified; they are not meaningful and
should not be referenced from prose.

## Failure mode

If rendering fails, `validate.sh` logs a note and continues — a broken renderer
must not block a validation run. §3 then states that no diagram was produced and
why. It does not fall back to a hand-drawn diagram presented as a generated one.
