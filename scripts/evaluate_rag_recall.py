from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys
from pathlib import Path
from statistics import mean
from typing import Any


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate VaultStream hybrid RAG recall.")
    parser.add_argument("--db", default="backend/data_eval/vaultstream.db")
    parser.add_argument("--ground-truth", default="docs/eval/rag_ground_truth.json")
    parser.add_argument("--out", default="docs/eval/rag_recall_report.json")
    parser.add_argument("--top-k", type=int, default=10)
    parser.add_argument("--max-queries", type=int, default=20)
    return parser.parse_args()


def _hit_rank(results: list[int], expected: set[int]) -> int | None:
    for idx, content_id in enumerate(results, start=1):
        if content_id in expected:
            return idx
    return None


async def _main() -> None:
    args = _parse_args()
    db_path = Path(args.db).resolve()
    os.environ["SQLITE_DB_PATH"] = str(db_path)
    sys.path.insert(0, str(Path("backend").resolve()))

    from app.core.database import init_db
    from app.core.db_adapter import AsyncSessionLocal, engine
    from app.services.embedding_service import EmbeddingService

    await init_db()

    ground_truth_path = Path(args.ground_truth)
    cases: list[dict[str, Any]] = json.loads(ground_truth_path.read_text(encoding="utf-8"))
    cases = cases[: max(1, args.max_queries)]
    service = EmbeddingService()

    rows: list[dict[str, Any]] = []
    source_counts: dict[str, int] = {}
    async with AsyncSessionLocal() as session:
        for case in cases:
            query = str(case["query"])
            expected = {int(x) for x in case["expected_content_ids"]}
            hits = await service.search(query=query, top_k=max(args.top_k, 10), session=session)
            result_ids = [hit.content.id for hit in hits]
            rank = _hit_rank(result_ids, expected)
            for hit in hits[: args.top_k]:
                source_counts[hit.match_source] = source_counts.get(hit.match_source, 0) + 1
            rows.append(
                {
                    "query": query,
                    "expected_content_ids": sorted(expected),
                    "returned_content_ids": result_ids[: args.top_k],
                    "hit_rank": rank,
                    "hit_at_5": rank is not None and rank <= 5,
                    "hit_at_10": rank is not None and rank <= 10,
                    "match_sources": [hit.match_source for hit in hits[: args.top_k]],
                }
            )

    total = max(1, len(rows))
    reciprocal_ranks = [0.0 if row["hit_rank"] is None else 1.0 / row["hit_rank"] for row in rows]
    report = {
        "db": args.db,
        "ground_truth": args.ground_truth,
        "query_count": len(rows),
        "top_k": args.top_k,
        "recall_at_5": sum(1 for row in rows if row["hit_at_5"]) / total,
        "recall_at_10": sum(1 for row in rows if row["hit_at_10"]) / total,
        "mrr": mean(reciprocal_ranks) if reciprocal_ranks else 0.0,
        "hit_source_distribution": source_counts,
        "failures": [row for row in rows if row["hit_rank"] is None],
        "cases": rows,
    }

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(_main())
