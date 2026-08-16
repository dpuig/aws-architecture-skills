# Knowledge Base

Provenance for the control catalog. **Not a skill package** — nothing here is
loaded at runtime.

```
knowledge-base/
├── sources/manifest.yaml   what was fetched, when, and what it yielded
└── curated/                YOUR corpus — absent by design, see below
```

## The three things called "the knowledge base"

They have different lifecycles and get confused constantly:

| Thing | Lives | Loaded at runtime |
|---|---|---|
| Upstream sources | `sources/manifest.yaml` — citations and fetch metadata | No |
| Distilled controls | `plugins/aws-architecture/skills/*/references/*.md` | Yes, on demand |
| Curated house corpus (`kb://`) | `curated/` — **does not exist yet** | Via `kb_search.py` |

## Why `curated/` is absent

It is gitignored and never shipped. Two reasons:

1. It is per-installation. A corpus inside a distributed package would be
   destroyed on every update.
2. It is the only genuinely proprietary part of this system. Every control in
   the catalog cites an `authority` (a public AWS or NIST source); **none cites
   a `kb_source`**, the field for your organisation's own position.

Point `kb_search.py` at yours:

```sh
export KB_ROOT=/path/to/curated
python3 plugins/aws-architecture/skills/aws-solution-architect/scripts/kb_search.py --build-index
```

Documents are Markdown with frontmatter:

```markdown
---
title: Deregistration delay sizing
domain: degradation
last_reviewed: 2026-08-15
---
```

An entry earns its place only if it contains a claim that would be *unknowable*
from outside your organisation — a measured threshold, an incident, a waiver and
its reasoning. An entry that restates the AWS documentation in different words
is worse than none: it inflates the coverage metric while adding nothing.

## Source content is not mirrored here

`sources/manifest.yaml` stores citations, fetch dates, and extracted assertions
in our own words. AWS documentation is copyrighted and CIS Benchmarks restrict
redistribution — see `/NOTICE`.
