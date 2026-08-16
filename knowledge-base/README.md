# Knowledge Base Corpus

Working area for Phase 1 ingestion. **Not a skill package** — nothing here is
loaded at runtime.

```
knowledge-base/
├── sources/
│   └── manifest.yaml       # what was fetched, when, and its license disposition
└── extracted/
    └── *-candidates.yaml   # candidate control records awaiting Phase 1.3 review
```

## Why this lives outside the skills

Three different things get confused as "the knowledge base," and they have
different lifecycles:

| Thing | Lives | Loaded at runtime |
|---|---|---|
| Upstream sources | Here, as citations + metadata | No |
| Candidate control records | Here, until reviewed | No |
| Distilled controls | `plugins/aws-architecture/skills/aws-zero-trust/references/*.md` | Yes, on demand |
| Curated house KB (`kb://`) | **Does not exist yet** — see below | Via `kb_search.py` |

Extraction is an authoring-time activity. The skill never reads this directory.
Once a candidate is reviewed and promoted into a domain reference file, the
substance has moved and the record here is history.

## License disposition

Source content is **not** mirrored into this repo. `sources/manifest.yaml` stores
citations, fetch dates, and extracted assertions in our own words — not copies.

- NIST material is public domain and may be quoted verbatim if ever needed.
- AWS documentation and whitepapers are copyrighted: cite and paraphrase only.
- CIS Benchmarks restrict redistribution: do not store the PDF here.

This matters because the plan contemplates distributing the skills as a plugin.
A repo containing mirrored copyrighted documentation is a much harder thing to
ship than one containing citations.

## Status

Pilot domain: **network** (ZT-NET). Chosen per the implementation plan — it is
the most checkable domain, so the schema meets a real validator soonest.

See `extracted/zt-net-candidates.yaml`.
