# VaultStream Current State and Roadmap

> Updated: 2026-06-06
> Purpose: current, code-backed direction for continued development. This file replaces the older long speculative V2 plan. Historical audit notes are archived under `docs/archive/`. Current product/security status is tracked in `docs/audits/2026-06-05-current-product-security-audit.md`.

## Current State

VaultStream is no longer just a prototype. It is a local-first content archive and distribution system with:

- FastAPI backend, SQLite persistence, background workers, platform adapters, distribution rules, SSE events, semantic search, and Agent tools.
- Flutter frontend with Home/Dynamics, Library, Inbox, Automation, settings, account center, onboarding/connect, and Agent assist pages.
- CI gates for backend tests, Python dependency audit, Bandit, OpenAPI docs inventory, SQLite schema gate, Flutter codegen/analyze/test, release image scan, and SBOM generation.

The current product direction should be:

1. Make self-hosting reliable and diagnosable.
2. Turn the archive into a useful personal knowledge base.
3. Keep Agent actions narrow, confirmed, audited, and reusable by the GUI.

## Verified Baseline

Recent local checks are summarized in `docs/audits/2026-06-05-current-product-security-audit.md`. The latest recorded results there are:

- Backend non-integration tests: 734 passed, 4 skipped, 16 deselected.
- Backend `ResourceWarning` error gate: 734 passed, 4 skipped, 16 deselected.
- Backend integration tests: 5 failed, 8 passed, 1 skipped, 2 xfailed.
- Flutter analyze: no issues found.
- Flutter test: 36 tests passed, with one existing non-fatal tap target warning.

Treat historical verification numbers in archived docs as snapshots, not current status.

## Core Backend Shape

Important current boundaries:

- Ingest entrypoints converge on `PostIngestService`, which coordinates summary, embedding, discovery patrol, and distribution hooks.
- FavoritesSync imports through `ContentService.create_share`; new favorites enter the parse queue, and already parsed duplicates trigger `PostIngestService` with `favorites_sync:<platform>` source metadata.
- Semantic search is exposed through `/search/semantic`, `/search/semantic/index-status`, and `/search/semantic/reindex`.
- Distribution decisions are centered on `DistributionService`; legacy engine/scheduler modules should stay thin compatibility wrappers until removed.
- Agent and GUI actions share a controlled tool/action surface. Dangerous writes require confirmation, and the internal API bridge is allowlist-only.

Main backend risks:

- Configuration is still split across `Settings`, DB settings, runtime mutation, and cache behavior.
- EventBus runtime state remains process-local; API diagnostics now read it through a public EventBus snapshot instead of route-level private field access.
- Background tasks have health state but not a full failure/retry operations panel.
- Several long task/adapter files still mix orchestration, parsing, media processing, and persistence.

## Core Frontend Shape

Important current boundaries:

- Feature modules live under `frontend/lib/features/`, with shared networking, layout, theme, and utilities under `core/` and `theme/`.
- Collection search supports keyword and semantic modes; semantic results carry score, match source, chunk title, and source text.
- Navigation is a `StatefulShellRoute.indexedStack` with detail pages pushed under the collection branch.
- Detail layouts are content-driven: portrait, article, gallery, video, and user profile layouts.

Main frontend risks:

- Some pages are still large Stateful widgets and should be split around state ownership, not just by visual sections.
- Shared-element motion between collection cards and detail pages has an initial shared-card fix. See `docs/known-issues/collection-card-detail-transition.md` for remaining visual validation.
- Discovery detail top overlap has been fixed; keep future Discovery layout work focused on reducing manual desktop layout complexity.
- Frontend test coverage is much thinner than backend coverage.

## Roadmap

### P0: Stabilize Current Product

Target: remove issues that make the current system feel unreliable.

- Visually verify and refine the collection card-to-detail shared transition across article, gallery, video, and text-only items.
- Watch the remaining intermittent full-suite `ResourceWarning` noise: the Agent/WebSocket SQLite worker leak and parsing/discovery background embedding leaks are fixed, but a default-warning run can still surface a proxy socket warning and one sqlite3 GC warning that do not reproduce as failures under `-W error::ResourceWarning`.

### P1: Architecture Convergence

Target: reduce drift between settings, tasks, and user-facing behavior.

- Introduce a typed `ConfigService` and migrate `settings_service` behind it.
- Model AI config explicitly: summary provider/model/key, embedding provider/model/key/dim, Agent chat provider/model/key.
- Keep `DistributionService` as the single distribution business entrypoint and remove old wrapper logic in a breaking cleanup release.
- Split `ContentParser` by responsibility: task orchestration, adapter parsing, archive media processing, post-ingest scheduling, and error/dead-letter handling.
- Convert high-value dynamic contracts into typed DTOs where they cross frontend/backend boundaries.

### P2: Operations and Observability

Target: make self-hosting and recovery straightforward.

- Add a background task diagnostics page: last run, last error, retry count, manual retry, and recent failure payload.
- Add failed embedding/reindex controls in settings or diagnostics.
- Add distribution queue failure details and retry history.
- Add backup/restore documentation for SQLite data, media storage, and config secrets.
- Keep OpenAPI and schema gates mandatory for endpoint or migration changes.

### P3: Knowledge Base and RAG

Target: make the archive useful beyond browsing.

- Improve semantic result presentation: visible chunk title, match snippet, score/source, and link to exact section where possible.
- Add content clustering and similar-content suggestions.
- Add RAG answer mode over selected scopes: library, discovery, tag set, platform, or date range.
- Keep the current SQLite JSON vector path until the documented thresholds are hit.
- Start a sqlite-vec feature-flagged pilot only when `content_embeddings` exceeds 50,000 rows, semantic search p95 exceeds 300ms, or candidate limits are repeatedly hit with relevance degradation.

### P4: Safe Agent Workflows

Target: make Agent useful without weakening system safety.

- Keep the allowlist-only API bridge. Do not add unrestricted SQL/table editing tools.
- Promote common workflows into first-class actions: tag cleanup, failed-task inspection, distribution preview, rule creation, favorites sync, and reindex planning.
- Generate or share frontend render models from tool result schemas where the UI needs richer rendering.
- Preserve preview/confirm for write, external side-effect, and dangerous operations.
- Record action/audit metadata for all confirmed writes.

## Development Rule of Thumb

For new work, prefer depth over breadth:

- Improve reliability, diagnostics, and contracts before adding another source platform.
- Add feature flags before introducing heavier indexing or runtime dependencies.
- Treat old audit docs as hypotheses, not source of truth. Current code plus checks decide status.
- When a fix closes a risk, add a reusable gate or diagnostic so the status does not drift again.
