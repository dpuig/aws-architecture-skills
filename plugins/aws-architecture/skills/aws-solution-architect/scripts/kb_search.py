#!/usr/bin/env python3
"""
Retrieval over the curated knowledge base.

Stable CLI contract — the skill depends on this shape, do not change it:

    kb_search.py "aurora global database failover rpo" --domain data --top-k 5
    → JSON: [{doc_id, title, snippet, kb_uri, score, last_reviewed}]

    kb_search.py --status        # is retrieval usable? exit 0 yes, 2 no
    kb_search.py --build-index   # (re)build the local index

Backend is BM25 with an exact-phrase boost, stdlib only — no runtime
dependency, works offline, versions alongside the skill. Dense retrieval is a
documented extension point (see rank()), deliberately not a requirement: the
corpus is full of exact-match tokens (service names, control IDs, CIDR
notation, API actions) where lexical scoring already does most of the work.

Corpus layout — each .md file carries frontmatter:

    ---
    title: Segment boundaries
    domain: network
    last_reviewed: 2026-02-01
    ---

kb:// URIs map to paths under the corpus root, so a `kb_source` of
kb://networking/segmentation.md resolves to <root>/networking/segmentation.md.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

# BM25 parameters. k1 controls term-frequency saturation, b controls
# length normalization. These are the standard defaults and have not been
# tuned against this corpus — revisit once there is an eval set.
K1 = 1.5
B = 0.75

# Multiplier applied when the full query string appears verbatim in a document.
# Control lookups are frequently exact ("ZT-NET-014", "0.0.0.0/0"), and pure
# bag-of-words scoring under-ranks those.
PHRASE_BOOST = 1.5

INDEX_VERSION = 1
SCRIPT_DIR = Path(__file__).resolve().parent

# The curated corpus belongs to the installation, not to this package — it is
# the one part of the system that is genuinely proprietary, so it is never
# bundled. Resolution order:
#   1. KB_ROOT              — explicit override, the supported production path
#   2. CLAUDE_PROJECT_DIR   — the user's project, when running under Claude Code
#   3. cwd                  — fallback for direct CLI use
# Deliberately NOT relative to this script: a corpus inside the plugin would be
# destroyed on every plugin update.
_PROJECT_ROOT = Path(os.environ.get("CLAUDE_PROJECT_DIR", ".")).resolve()

DEFAULT_CORPUS = Path(
    os.environ.get("KB_ROOT") or _PROJECT_ROOT / "knowledge-base" / "curated"
)
DEFAULT_INDEX = Path(
    os.environ.get("KB_INDEX") or _PROJECT_ROOT / "knowledge-base" / ".kb-index.json"
)

# Keeps dotted, slashed, hyphenated and colon-joined technical tokens intact:
# "0.0.0.0/0", "ZT-NET-014", "s3:GetObject", "us-east-1" survive tokenization.
TOKEN_RE = re.compile(r"[a-z0-9][a-z0-9._/:-]*")


def tokenize(text: str) -> list[str]:
    return TOKEN_RE.findall(text.lower())


def parse_frontmatter(raw: str) -> tuple[dict, str]:
    """Minimal frontmatter parser. Flat `key: value` pairs only — deliberately
    not a YAML dependency, since the corpus format is ours to keep simple."""
    if not raw.startswith("---"):
        return {}, raw
    end = raw.find("\n---", 3)
    if end == -1:
        return {}, raw
    block, body = raw[3:end], raw[end + 4 :]
    meta = {}
    for line in block.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        meta[key.strip()] = value.strip().strip("\"'")
    return meta, body.lstrip("\n")


def build_index(corpus: Path, index_path: Path) -> dict:
    if not corpus.is_dir():
        die_no_corpus(corpus)

    docs, df = [], Counter()
    for path in sorted(corpus.rglob("*.md")):
        raw = path.read_text(encoding="utf-8", errors="replace")
        meta, body = parse_frontmatter(raw)
        tokens = tokenize(body)
        if not tokens:
            continue
        tf = Counter(tokens)
        rel = path.relative_to(corpus).as_posix()
        docs.append(
            {
                "doc_id": rel,
                "title": meta.get("title", path.stem.replace("-", " ")),
                "domain": meta.get("domain", "unclassified"),
                "last_reviewed": meta.get("last_reviewed"),
                "kb_uri": f"kb://{rel}",
                "len": len(tokens),
                "tf": dict(tf),
                "text": body,
            }
        )
        df.update(tf.keys())

    if not docs:
        die_no_corpus(corpus, reason="corpus directory contains no indexable .md files")

    index = {
        "version": INDEX_VERSION,
        "built": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "corpus_root": str(corpus),
        "doc_count": len(docs),
        "avg_len": sum(d["len"] for d in docs) / len(docs),
        "df": dict(df),
        "docs": docs,
    }
    index_path.parent.mkdir(parents=True, exist_ok=True)
    index_path.write_text(json.dumps(index), encoding="utf-8")
    return index


def load_index(index_path: Path, corpus: Path) -> dict:
    if not index_path.exists():
        if corpus.is_dir():
            return build_index(corpus, index_path)
        die_no_corpus(corpus)
    try:
        index = json.loads(index_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        fail(f"index at {index_path} is corrupt; re-run with --build-index", code=2)
    if index.get("version") != INDEX_VERSION:
        return build_index(corpus, index_path)
    return index


def rank(index: dict, query: str, domain: str | None, top_k: int) -> list[dict]:
    """BM25 + exact-phrase boost.

    Extension point: to add dense retrieval, score documents with a vector
    model here and combine with reciprocal rank fusion rather than a weighted
    sum — RRF avoids having to calibrate two incomparable score scales.
    """
    terms = tokenize(query)
    if not terms:
        return []

    n = index["doc_count"]
    avg_len = index["avg_len"] or 1.0
    df = index["df"]
    phrase = query.lower().strip()

    idf = {}
    for term in set(terms):
        d = df.get(term, 0)
        # Standard BM25 idf. Floored at a small positive value so that a term
        # present in every document contributes ~nothing rather than negatively.
        idf[term] = max(math.log(1 + (n - d + 0.5) / (d + 0.5)), 1e-6)

    results = []
    for doc in index["docs"]:
        if domain and doc.get("domain") != domain:
            continue
        tf = doc["tf"]
        norm = K1 * (1 - B + B * doc["len"] / avg_len)
        score = 0.0
        matched = []
        for term in terms:
            f = tf.get(term, 0)
            if not f:
                continue
            score += idf[term] * (f * (K1 + 1)) / (f + norm)
            matched.append(term)
        if score <= 0:
            continue
        if len(phrase) > 3 and phrase in doc["text"].lower():
            score *= PHRASE_BOOST
        results.append((score, doc, matched))

    results.sort(key=lambda r: (-r[0], r[1]["doc_id"]))
    return [
        {
            "doc_id": doc["doc_id"],
            "title": doc["title"],
            "snippet": snippet(doc["text"], matched),
            "kb_uri": doc["kb_uri"],
            "score": round(score, 4),
            "last_reviewed": doc.get("last_reviewed"),
        }
        for score, doc, matched in results[:top_k]
    ]


def snippet(text: str, matched: list[str], width: int = 320) -> str:
    """Return the window with the highest density of matched terms."""
    lowered = text.lower()
    best_pos, best_hits = 0, -1
    positions = [lowered.find(t) for t in matched]
    positions = [p for p in positions if p >= 0] or [0]
    for start in positions:
        window = lowered[start : start + width]
        hits = sum(window.count(t) for t in matched)
        if hits > best_hits:
            best_hits, best_pos = hits, start
    begin = max(0, best_pos - 40)
    excerpt = " ".join(text[begin : begin + width].split())
    prefix = "…" if begin > 0 else ""
    suffix = "…" if begin + width < len(text) else ""
    return f"{prefix}{excerpt}{suffix}"


def die_no_corpus(corpus: Path, reason: str | None = None) -> None:
    """Exit 2 with a machine-readable payload.

    Exit code 2 is meaningful: it tells the skill that retrieval is unavailable,
    so claims must be marked UNGROUNDED rather than silently answered from model
    recall. Failing loudly here is the whole point — a retrieval layer that
    returns nothing and exits 0 is indistinguishable from one that found nothing
    relevant, and those must not be confused.
    """
    fail(
        reason or f"no curated knowledge base at {corpus}",
        code=2,
        hint=(
            "Set KB_ROOT, or create the corpus. Until it exists, every claim not "
            "covered by a catalog control must be marked UNGROUNDED."
        ),
    )


def fail(message: str, code: int = 1, hint: str | None = None) -> None:
    payload = {"error": message, "results": []}
    if hint:
        payload["hint"] = hint
    json.dump(payload, sys.stdout, indent=2)
    sys.stdout.write("\n")
    sys.exit(code)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Retrieval over the curated knowledge base."
    )
    parser.add_argument("query", nargs="?", help="free-text query")
    parser.add_argument("--domain", help="restrict to one domain")
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--index", type=Path, default=DEFAULT_INDEX)
    parser.add_argument("--build-index", action="store_true")
    parser.add_argument("--status", action="store_true")
    args = parser.parse_args()

    if args.build_index:
        index = build_index(args.corpus, args.index)
        json.dump(
            {
                "built": index["built"],
                "doc_count": index["doc_count"],
                "corpus_root": index["corpus_root"],
                "index": str(args.index),
            },
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0

    if args.status:
        if not args.corpus.is_dir():
            die_no_corpus(args.corpus)
        index = load_index(args.index, args.corpus)
        json.dump(
            {
                "status": "ok",
                "corpus_root": index["corpus_root"],
                "doc_count": index["doc_count"],
                "built": index["built"],
                "domains": sorted({d["domain"] for d in index["docs"]}),
            },
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0

    if not args.query:
        fail("a query is required (or use --status / --build-index)", code=1)

    index = load_index(args.index, args.corpus)
    json.dump(rank(index, args.query, args.domain, args.top_k), sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
