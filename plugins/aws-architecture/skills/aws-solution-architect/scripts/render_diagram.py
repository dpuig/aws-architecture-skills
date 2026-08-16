#!/usr/bin/env python3
"""
Render the planned architecture as a Mermaid diagram and/or an ASCII tree.

    render_diagram.py <plan.json> [--format mermaid|ascii|both] [--out DIR]

The diagram is derived from `plan.json` — the same artifact Stage 1 of
validate.sh produces and every later stage reads. That is the whole point of
generating it here rather than drawing it by hand.

Design rule, enforced throughout: **the diagram may only show what the plan
contains.** A hand-drawn architecture diagram is the most persuasive artifact in
any deliverable and the least verifiable, which is exactly the combination this
system exists to prevent. So:

  - Placement is read from explicit plan references, never guessed. A resource
    whose subnet is not resolvable at plan time is rendered in an explicit
    "placement unknown at plan time" bucket, never quietly dropped into a subnet
    to make the picture tidier.
  - Attributes that are known-after-apply render as `?`, not as a plausible
    value.
  - Every rendering decision that discarded information is counted in the
    provenance footer, so the reader can tell a simple architecture from a
    partially-understood one.

An empty diagram is a correct output for an empty plan. A pretty diagram that
implies structure the Terraform does not create is not.
"""

import argparse
import json
import re
import sys
from collections import defaultdict, OrderedDict

# Sentinel carried in the region variable's `description`. See references/
# diagrams.md and intake-schema.md. It lives in the description because a fake
# region *value* passes `terraform validate` but fails `terraform plan`
# ("invalid AWS Region"), which would take down Stage 1 and with it the entire
# deliverable — the placeholder has to be a real, plannable Region.
REGION_PLACEHOLDER_TOKEN = "REGION-PLACEHOLDER"
REGION_UNSPECIFIED_LABEL = "<REGION UNSPECIFIED>"

# Reference arguments that express *containment*. Nesting already shows these,
# so drawing them as edges too would double every line in the diagram.
CONTAINMENT_ARGS = {
    "vpc_id", "subnet_id", "subnet_ids", "availability_zone",
    "availability_zones", "vpc_zone_identifier",
}

# Resources that are boundaries in their own right rather than things sitting
# inside one. Rendered as the containers, not as leaf nodes.
CONTAINER_TYPES = {"aws_vpc", "aws_subnet"}


# ---------------------------------------------------------------------------
# Plan traversal
# ---------------------------------------------------------------------------

def walk_values(mod, prefix=""):
    """Yield (address, resource) from planned_values, descending into modules."""
    for r in mod.get("resources", []) or []:
        yield r.get("address", prefix + r.get("name", "?")), r
    for child in mod.get("child_modules", []) or []:
        yield from walk_values(child, prefix)


def walk_config(mod, prefix=""):
    """Yield (address, resource) from configuration, descending into modules.

    Child-module references are expressed relative to their own module, so the
    prefix is carried through and cross-module references are left unresolved
    rather than guessed at. See `unresolved_refs` in the footer.
    """
    for r in mod.get("resources", []) or []:
        yield prefix + r.get("address", ""), r
    for name, call in (mod.get("module_calls") or {}).items():
        yield from walk_config(call.get("module") or {}, f"{prefix}module.{name}.")


def strip_index(addr):
    """`aws_subnet.a[0]` -> `aws_subnet.a`, to match planned against config."""
    return re.sub(r"\[[^\]]*\]", "", addr)


def walk_expr(node):
    """Yield every reference string in an expression tree.

    Terraform nests block arguments as lists of expression maps — an ASG's
    `launch_template { id = aws_launch_template.lt.id }` lands two levels down.
    Reading only top-level `references` silently loses those edges, which is how
    a diagram ends up showing fewer relationships than the plan actually has.
    """
    if isinstance(node, dict):
        for ref in node.get("references") or []:
            yield ref
        for key, value in node.items():
            if key in ("references", "constant_value"):
                continue
            yield from walk_expr(value)
    elif isinstance(node, list):
        for item in node:
            yield from walk_expr(item)


# Reference prefixes that never name a resource. Counting these as unresolved
# would inflate the footer's "not resolved" figure with `each.key`, `count.index`
# and variable lookups, which are not missing nodes at all.
NON_RESOURCE_REF_PREFIXES = (
    "var.", "local.", "each.", "count.", "path.", "terraform.", "self.",
)


def resolve_ref(ref, exact, collections):
    """Resolve a reference to the resource instances it names.

    Returns a list, because one reference can name several instances. The two
    cases must not be conflated, and both appear in ordinary Terraform:

      aws_subnet.private["a"].id   -> exactly that instance
      aws_subnet.private           -> every instance of the collection

    Resolving the first to the whole collection would draw a single-AZ resource
    as multi-AZ; resolving the second to just one instance would draw a
    multi-AZ resource as single-AZ. Both are the same class of lie about
    failure domains, in opposite directions — so an exact indexed match is
    always tried before the collection falls back.

    References carry an attribute suffix that varies by resource (`.id`, `.arn`,
    `.name`, or a nested path), so matching trims trailing segments until an
    address is hit rather than stripping a fixed list of known suffixes.

    Returns (targets, is_exact). `is_exact` tells the caller this reference
    named one instance, which matters because Terraform lists *every* form of a
    reference together — see `arg_targets`.
    """
    parts = ref.split(".")
    while len(parts) >= 2:
        cand = ".".join(parts)
        if cand in exact:
            return [cand], True
        if cand == strip_index(cand) and cand in collections:
            return list(collections[cand]), False
        parts.pop()
    return [], False


def is_resource_ref(ref):
    return not ref.startswith(NON_RESOURCE_REF_PREFIXES)


# ---------------------------------------------------------------------------
# Region
# ---------------------------------------------------------------------------

def resolve_region(plan):
    """Return (label, placeholder: bool, note).

    Three outcomes, and they are deliberately distinguishable:
      - a real Region stated in the config          -> ("eu-west-1", False, ...)
      - the placeholder sentinel                    -> (UNSPECIFIED, True, ...)
      - no resolvable Region at all                 -> (UNSPECIFIED, True, ...)

    The third case is treated as unspecified rather than as an error: a plan
    that never pins a Region has the same consequence for the reader as one that
    pins a placeholder, and both must reach the deliverable as a question.
    """
    config = plan.get("configuration") or {}
    providers = config.get("provider_config") or {}
    variables = (config.get("root_module") or {}).get("variables") or {}

    for name, pcfg in providers.items():
        if not (name == "aws" or str(pcfg.get("name", "")) == "aws"):
            continue
        expr = (pcfg.get("expressions") or {}).get("region") or {}

        if "constant_value" in expr:
            return str(expr["constant_value"]), False, "declared in provider block"

        for ref in expr.get("references") or []:
            if not ref.startswith("var."):
                continue
            var = variables.get(ref[4:]) or {}
            desc = str(var.get("description") or "")
            default = var.get("default")
            if REGION_PLACEHOLDER_TOKEN in desc:
                shown = default if default is not None else "?"
                return (REGION_UNSPECIFIED_LABEL, True,
                        f"placeholder; plans against {shown} pending a decision")
            if default is not None:
                return str(default), False, f"default of {ref}"
            return (REGION_UNSPECIFIED_LABEL, True,
                    f"{ref} has no default — supplied at apply time")

    return REGION_UNSPECIFIED_LABEL, True, "no Region resolvable from the plan"


# ---------------------------------------------------------------------------
# Topology assembly
# ---------------------------------------------------------------------------

class Topology:
    def __init__(self):
        self.region = REGION_UNSPECIFIED_LABEL
        self.region_placeholder = True
        self.region_note = ""
        self.vpcs = OrderedDict()        # vpc addr -> {"cidr", "azs": {az: [sn]}}
        self.subnets = OrderedDict()     # subnet addr -> {"vpc","az","cidr","public"}
        self.in_subnet = defaultdict(list)   # subnet addr -> [resource]
        self.in_az = defaultdict(list)       # (vpc, az)   -> [resource]
        self.vpc_scoped = defaultdict(list)  # vpc addr    -> [resource]
        self.spanning = defaultdict(list)    # vpc addr|"" -> [(resource, azs)]
        self.regional = []
        self.unknown_placement = []
        self.edges = []
        self.unresolved_refs = 0
        self.total_resources = 0


def summarize(addr, res):
    """A short, honest label. Unknown-at-plan-time renders as `?`, never guessed."""
    v = res.get("values") or {}
    t = res.get("type", "")
    bits = []

    def add(key, fmt="{}"):
        if key in v and v[key] not in (None, ""):
            bits.append(fmt.format(v[key]))

    if t == "aws_db_instance" or t == "aws_rds_cluster":
        add("engine")
        if v.get("multi_az") is True or t == "aws_rds_cluster":
            bits.append("multi-AZ")
    elif t == "aws_lb_target_group":
        proto, port = v.get("protocol"), v.get("port")
        bits.append(f"{proto or '?'}:{port if port is not None else '?'}")
    elif t == "aws_lb":
        add("load_balancer_type")
        bits.append("internal" if v.get("internal") else "internet-facing")
    elif t in ("aws_ecs_service", "aws_autoscaling_group"):
        for k in ("desired_count", "desired_capacity", "min_size"):
            if v.get(k) is not None:
                bits.append(f"{k.replace('_', ' ')} {v[k]}")
                break
    elif t == "aws_s3_bucket":
        add("bucket")

    return f"{addr}" + (f"  [{', '.join(str(b) for b in bits)}]" if bits else "")


def build(plan):
    topo = Topology()
    topo.region, topo.region_placeholder, topo.region_note = resolve_region(plan)

    root_values = (plan.get("planned_values") or {}).get("root_module") or {}
    resources = OrderedDict()
    for addr, res in walk_values(root_values):
        resources[addr] = res
    topo.total_resources = len(resources)

    # Two indexes: exact planned addresses, and de-indexed collection names
    # mapping to every instance under them. resolve_ref needs both to tell
    # `aws_subnet.private["a"]` from `aws_subnet.private`.
    exact = set(resources)
    collections = defaultdict(list)
    for addr in resources:
        collections[strip_index(addr)].append(addr)

    # Configuration references, keyed by de-indexed address then by the
    # top-level argument the reference appeared under.
    config_refs = {}
    for addr, res in walk_config((plan.get("configuration") or {}).get("root_module") or {}):
        refs = {}
        for arg, expr in (res.get("expressions") or {}).items():
            found = list(walk_expr(expr))
            if found:
                refs[arg] = found
        config_refs[strip_index(addr)] = refs

    def refs_of(addr, arg):
        return (config_refs.get(strip_index(addr)) or {}).get(arg) or []

    def arg_targets(addr, arg, count_unresolved=False):
        """Resources named by one argument, at the finest available granularity.

        Terraform lists every form of a reference side by side — a single
        `aws_subnet.private["a"].id` appears as that, plus `...["a"]`, plus the
        bare `aws_subnet.private`. Taking the union of those pulls in the whole
        collection and would show a resource sitting in one subnet as spanning
        all of them. So references are grouped by the resource they name, and
        within each group an exact instance match wins over the collection.
        """
        by_base = OrderedDict()
        for ref in refs_of(addr, arg):
            if not is_resource_ref(ref):
                continue          # `each.key`, `count.index`, `var.x` — not nodes
            targets, is_exact = resolve_ref(ref, exact, collections)
            if not targets:
                if count_unresolved:
                    # Names a resource that is not in this plan — a cross-module
                    # reference, or one resolved outside it.
                    topo.unresolved_refs += 1
                continue
            slot = by_base.setdefault(strip_index(targets[0]), {"exact": [], "coll": []})
            slot["exact" if is_exact else "coll"].extend(targets)

        chosen = []
        for slot in by_base.values():
            for target in (slot["exact"] or slot["coll"]):
                if target not in chosen:
                    chosen.append(target)
        return chosen

    def all_refs(addr, args, of_type):
        """Every distinct resource of `of_type` referenced by any of `args`."""
        found = []
        for arg in args:
            for target in arg_targets(addr, arg):
                if resources[target].get("type") == of_type and target not in found:
                    found.append(target)
        return found

    def first_ref(addr, args, of_type):
        found = all_refs(addr, args, of_type)
        return found[0] if found else None

    # --- containers first: VPCs, then subnets placed into them ---------------
    for addr, res in resources.items():
        if res.get("type") != "aws_vpc":
            continue
        topo.vpcs[addr] = {"cidr": (res.get("values") or {}).get("cidr_block") or "?",
                           "azs": OrderedDict()}

    for addr, res in resources.items():
        if res.get("type") != "aws_subnet":
            continue
        v = res.get("values") or {}
        vpc = first_ref(addr, ("vpc_id",), "aws_vpc")
        az = v.get("availability_zone") or "?"
        topo.subnets[addr] = {
            "vpc": vpc, "az": az,
            "cidr": v.get("cidr_block") or "?",
            # Only an explicit signal counts. Absent that the tier is unknown,
            # and "unknown" is rendered as such rather than assumed private —
            # a subnet mislabelled private in a diagram is a security claim.
            "public": v.get("map_public_ip_on_launch"),
        }
        if vpc is None:
            topo.vpcs.setdefault("(no VPC in plan)", {"cidr": "?", "azs": OrderedDict()})
            vpc = "(no VPC in plan)"
            topo.subnets[addr]["vpc"] = vpc
        topo.vpcs[vpc]["azs"].setdefault(az, []).append(addr)

    # --- everything else -----------------------------------------------------
    for addr, res in resources.items():
        t = res.get("type", "")
        if t in CONTAINER_TYPES:
            continue
        v = res.get("values") or {}

        entry = (addr, summarize(addr, res))

        placed_in = all_refs(addr, ("subnet_id", "subnet_ids", "vpc_zone_identifier"),
                             "aws_subnet")
        if len(placed_in) == 1:
            topo.in_subnet[placed_in[0]].append(entry)
            continue
        if len(placed_in) > 1:
            # Spans several subnets. Drawing it inside one of them would show a
            # multi-AZ deployment as single-AZ — the exact property the ZD-TOP
            # controls are about, misrepresented in the artifact people trust
            # most.
            spanned_azs = []
            for sn in placed_in:
                az = topo.subnets.get(sn, {}).get("az", "?")
                if az not in spanned_azs:
                    spanned_azs.append(az)
            vpc = topo.subnets.get(placed_in[0], {}).get("vpc") or ""
            topo.spanning[vpc].append((addr, summarize(addr, res), spanned_azs))
            continue

        az_list = v.get("availability_zones")
        if isinstance(az_list, list) and az_list:
            vpc = first_ref(addr, ("vpc_id",), "aws_vpc") or ""
            topo.spanning[vpc].append((addr, summarize(addr, res), list(az_list)))
            continue

        az = v.get("availability_zone")
        vpc = first_ref(addr, ("vpc_id",), "aws_vpc")
        if az and vpc:
            topo.in_az[(vpc, az)].append(entry)
            continue
        if vpc:
            topo.vpc_scoped[vpc].append(entry)
            continue

        # A resource that names a subnet/AZ argument whose value is not
        # resolvable at plan time. Rendering it as regional would be a lie.
        declared_placement = any(
            arg in (res.get("values") or {}) or refs_of(addr, arg)
            for arg in ("subnet_id", "subnet_ids", "availability_zone",
                        "availability_zones", "vpc_zone_identifier", "vpc_id")
        )
        if declared_placement:
            topo.unknown_placement.append(entry)
        else:
            topo.regional.append(entry)

    # --- edges ---------------------------------------------------------------
    # Unresolved references are counted here, once per resource, rather than in
    # the placement pass — placement queries only a few arguments, so counting
    # there would report a figure that depends on which buckets happened to be
    # consulted.
    seen_edges = set()
    for addr in resources:
        for arg in (config_refs.get(strip_index(addr)) or {}):
            targets = arg_targets(addr, arg, count_unresolved=True)
            if arg in CONTAINMENT_ARGS:
                continue          # nesting already shows these
            for target in targets:
                if resources[target].get("type") in CONTAINER_TYPES or target == addr:
                    continue
                key = (addr, target, arg)
                if key in seen_edges:
                    continue
                seen_edges.add(key)
                topo.edges.append(key)

    return topo


# ---------------------------------------------------------------------------
# Mermaid
# ---------------------------------------------------------------------------

def mermaid_id(addr):
    return "n_" + re.sub(r"[^0-9a-zA-Z]+", "_", addr).strip("_")


def esc(text):
    """Mermaid labels are quoted; quotes and brackets inside them break parsing."""
    return str(text).replace('"', "'").replace("[", "(").replace("]", ")")


def subnet_tier(meta):
    if meta["public"] is True:
        return "public"
    if meta["public"] is False:
        return "private"
    return "tier unknown"


def render_mermaid(topo):
    L = ["flowchart TB"]
    emitted = {}      # node id -> class
    node_of = {}      # resource address -> node id

    def leaf(addr, label, cls, indent):
        nid = f"{mermaid_id(addr)}_{len(emitted)}"
        emitted[nid] = cls
        node_of.setdefault(addr, nid)
        L.append(f'{" " * indent}{nid}["{esc(label)}"]')
        return nid

    region_label = f"Region: {topo.region}"
    if topo.region_placeholder:
        region_label += "  (!)"
    L.append(f'  subgraph reg["{esc(region_label)}"]')

    for vpc, meta in topo.vpcs.items():
        L.append(f'    subgraph {mermaid_id(vpc)}["{esc("VPC " + vpc + " - " + str(meta["cidr"]))}"]')
        for az, subnets in meta["azs"].items():
            L.append(f'      subgraph {mermaid_id(vpc + az)}["{esc("AZ " + az)}"]')
            for sn in subnets:
                s = topo.subnets[sn]
                label = f"subnet {sn} ({subnet_tier(s)}) {s['cidr']}"
                L.append(f'        subgraph {mermaid_id(sn)}["{esc(label)}"]')
                placed = topo.in_subnet.get(sn, [])
                if placed:
                    for addr, label_r in placed:
                        leaf(addr, label_r, "res", 10)
                else:
                    # Mermaid renders an empty subgraph as a bare label that is
                    # easily misread as a resource. An explicit spacer keeps
                    # "declared but empty" visually distinct from "occupied".
                    leaf(f"{sn}__empty", "(no resources placed here)", "empty", 10)
                L.append("        end")
            for addr, label_r in topo.in_az.get((vpc, az), []):
                leaf(addr, label_r, "res", 8)
            L.append("      end")

        if topo.spanning.get(vpc):
            L.append(f'      subgraph {mermaid_id(vpc + "_span")}["Spans AZs"]')
            for addr, label_r, azs in topo.spanning[vpc]:
                leaf(addr, f"{label_r} -> {', '.join(azs)}", "res", 8)
            L.append("      end")

        if topo.vpc_scoped.get(vpc):
            L.append(f'      subgraph {mermaid_id(vpc + "_scoped")}["VPC-scoped"]')
            for addr, label_r in topo.vpc_scoped[vpc]:
                leaf(addr, label_r, "res", 8)
            L.append("      end")
        L.append("    end")

    if topo.spanning.get(""):
        L.append('    subgraph span_no_vpc["Spans AZs (no VPC reference)"]')
        for addr, label_r, azs in topo.spanning[""]:
            leaf(addr, f"{label_r} -> {', '.join(azs)}", "res", 6)
        L.append("    end")

    if topo.regional:
        L.append('    subgraph regional["Regional / not VPC-bound"]')
        for addr, label_r in topo.regional:
            leaf(addr, label_r, "res", 6)
        L.append("    end")
    L.append("  end")

    if topo.unknown_placement:
        L.append('  subgraph unknown["(!) Placement unknown at plan time"]')
        for addr, label_r in topo.unknown_placement:
            leaf(addr, label_r, "unk", 4)
        L.append("  end")

    # Real edges between emitted nodes. An endpoint that was never drawn (a
    # container, or a resource outside this plan) is skipped rather than pointed
    # at an arbitrary stand-in node.
    for src, dst, arg in topo.edges:
        a, b = node_of.get(src), node_of.get(dst)
        if a and b:
            L.append(f"  {a} -->|{esc(arg)}| {b}")

    L += [
        "  classDef res fill:#eef4ff,stroke:#5b7fbd,color:#12263f;",
        "  classDef unk fill:#fff4e5,stroke:#c47f17,color:#4a3208,stroke-dasharray:4 3;",
        "  classDef empty fill:#f6f6f6,stroke:#bbbbbb,color:#666666,stroke-dasharray:2 2;",
    ]
    for cls in ("res", "unk", "empty"):
        members = [n for n, c in emitted.items() if c == cls]
        if members:
            L.append(f"  class {','.join(members)} {cls};")
    return "\n".join(L)


# ---------------------------------------------------------------------------
# ASCII
# ---------------------------------------------------------------------------

def render_ascii(topo):
    L = []
    header = f"Region: {topo.region}"
    L.append(header)
    L.append("=" * max(len(header), 40))
    if topo.region_placeholder:
        L.append(f"  !! {topo.region_note}")
    else:
        L.append(f"  ({topo.region_note})")
    L.append("")

    def block(lines, indent):
        for ln in lines:
            L.append(" " * indent + ln)

    for vpc, meta in topo.vpcs.items():
        L.append(f"VPC {vpc}  {meta['cidr']}")
        for az, subnets in meta["azs"].items():
            L.append(f"  +- AZ {az}")
            for sn in subnets:
                s = topo.subnets[sn]
                L.append(f"  |  +- subnet {sn}  {subnet_tier(s)}  {s['cidr']}")
                res = topo.in_subnet.get(sn, [])
                if not res:
                    L.append("  |  |    (no resources placed here)")
                for _addr, label in res:
                    L.append(f"  |  |    - {label}")
            for _addr, label in topo.in_az.get((vpc, az), []):
                L.append(f"  |    - {label}")

        for _addr, label, azs in topo.spanning.get(vpc, []):
            L.append(f"  +- spans AZs {', '.join(azs)}")
            L.append(f"  |    - {label}")
        if topo.vpc_scoped.get(vpc):
            L.append("  +- VPC-scoped")
            for _addr, label in topo.vpc_scoped[vpc]:
                L.append(f"  |    - {label}")
        L.append("")

    if topo.spanning.get(""):
        L.append("Spans AZs (no VPC reference)")
        for _addr, label, azs in topo.spanning[""]:
            L.append(f"  - {label}  ->  {', '.join(azs)}")
        L.append("")

    if topo.regional:
        L.append("Regional / not VPC-bound")
        for _addr, label in topo.regional:
            L.append(f"  - {label}")
        L.append("")

    if topo.unknown_placement:
        L.append("!! Placement unknown at plan time")
        L.append("   These declare a subnet, AZ, or VPC whose value is not known")
        L.append("   until apply. They are NOT drawn inside a boundary above.")
        for _addr, label in topo.unknown_placement:
            L.append(f"  - {label}")
        L.append("")

    if topo.edges:
        L.append("References (non-containment)")
        for src, dst, arg in topo.edges:
            L.append(f"  {src}  --{arg}-->  {dst}")
        L.append("")

    block(provenance(topo), 0)
    return "\n".join(L)


def provenance(topo):
    lines = [
        "-- Provenance --------------------------------------------------------",
        f"Derived from plan.json. Resources in plan: {topo.total_resources}.",
        "Nothing in this diagram is inferred; placement comes from explicit plan",
        "references only.",
    ]
    if topo.unknown_placement:
        lines.append(f"Unplaced (unknown at plan time): {len(topo.unknown_placement)}.")
    if topo.unresolved_refs:
        lines.append(f"References naming a resource outside this plan: {topo.unresolved_refs}.")
    if topo.region_placeholder:
        lines.append("Region is a PLACEHOLDER — see the deliverable header.")
    return lines


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("plan", help="path to plan.json (from `terraform show -json`)")
    ap.add_argument("--format", choices=("mermaid", "ascii", "both"), default="both")
    ap.add_argument("--out", help="directory to write architecture.mmd / architecture.txt")
    ap.add_argument("--region-status", action="store_true",
                    help="print JSON describing the resolved Region and exit")
    args = ap.parse_args()

    try:
        with open(args.plan) as fh:
            plan = json.load(fh)
    except FileNotFoundError:
        print(f"render_diagram: no such plan file: {args.plan}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as exc:
        print(f"render_diagram: {args.plan} is not valid JSON: {exc}", file=sys.stderr)
        return 2

    if args.region_status:
        label, placeholder, note = resolve_region(plan)
        print(json.dumps({"region": label, "placeholder": placeholder, "note": note}))
        return 0

    topo = build(plan)
    outputs = {}
    if args.format in ("mermaid", "both"):
        outputs["architecture.mmd"] = render_mermaid(topo)
    if args.format in ("ascii", "both"):
        outputs["architecture.txt"] = render_ascii(topo)

    if args.out:
        import os
        os.makedirs(args.out, exist_ok=True)
        for name, body in outputs.items():
            with open(os.path.join(args.out, name), "w") as fh:
                fh.write(body + "\n")
            print(f"  diagram: {os.path.join(args.out, name)}", file=sys.stderr)
    else:
        for i, (name, body) in enumerate(outputs.items()):
            if i:
                print()
            print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
