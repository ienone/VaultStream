# Review, Queue, and Push Upgrade Design

This document reviews the current Review, Queue, and Push behavior and proposes upgrades for queue management, personalized push configuration, and QQ (Napcat) support.

---

## 📊 Implementation Progress at a Glance

| Phase | Description | Progress | Status |
|-------|-------------|----------|--------|
| **Phase 1** | Backend Foundation (render_config + Napcat + merge forward) | 100% | ✅ Complete |
| **Phase 2** | Queue Enhancements (APIs + scheduler + events) | 100% | ✅ Complete |
| **Phase 3** | Frontend Queue Dashboard (Material 3 + drag-drop + responsive) | 95% | ⚠️ Near Complete |
| **Phase 4** | Rule/Target Management (editors + config override) | 85% | ⚠️ Missing standalone target page |

**Last Updated**: 2026-02-09

---

## 1. Current State

### 1.1 Review & Queue
- Current:
  - Queue is a virtual list from SQL queries.
  - Query: `SELECT * FROM contents WHERE review_status='APPROVED' AND status='PULLED' AND scheduled_at <= NOW() ORDER BY queue_priority DESC, scheduled_at ASC`.
  - `DistributionScheduler` polls every 60 seconds and pulls 50 items.
- Issues:
  - No intuitive FIFO visualization.
  - Hard to insert, reorder, or move items (only `queue_priority`).
  - No explicit in-progress state lock (single worker today).

### 1.2 Push Config
- Current:
  - `DistributionRule` defines source -> target.
  - Push formatting is hardcoded in `TelegramPushService`.
- Issues:
  - All groups receive identical formatting.
  - Cannot hide fields per target (author, links, text-only).

### 1.3 Channel Expansion
- Current:
  - Only Telegram Bot API supported.
- Needs:
  - QQ integration via Napcat/OneBot 11.
  - Batch forward to avoid spam.

---

## 2. Design

### Part 1: Queue Standardization

Goal: controllable FIFO queue with precise scheduling, immediate push, and batch operations.

#### Backend

1. Scheduling logic:
   - Today uses `scheduled_at`. Approved content is placed at the next polling window.
   - Immediate Push Mode:
     1. Set `scheduled_at = utcnow()`.
     2. Set `queue_priority = 9999`.
     3. Call `Scheduler.trigger_run()` to wake immediately.
   - Batch grouping: items with the same `scheduled_at` are merged and sent together.

2. API Plan:
   - `GET /items`: Frontend groups by `scheduled_at`.
   - `POST /queue/batch-reschedule`: Batch scheduling and grouping.
   - `POST /queue/batch-push-now`: Immediate push.

#### Frontend

- Timeline View:
  - Desktop: dual column with timeline + cards.
  - Mobile: single column with time headers.
- Cards:
  - Single card: cover, title, platform chips.
  - Batch group: nested cards with count header.
- Interactions:
  - Drag to reorder and snap to time points.
  - Multi-select and merge.
  - Upcoming items highlighted.

---

### Part 2: Personalized Push Content

Goal: render configuration per rule/target.

#### Backend

`render_config` structure:

```json
{
  "template_engine": "jinja2",
  "structure": {
    "header_text": "Daily picks",
    "footer_text": "",
    "show_platform_id": true,
    "show_title": true,
    "show_tags": false,
    "author_mode": "full",
    "content_mode": "summary",
    "media_mode": "auto",
    "link_mode": "clean"
  }
}
```

#### Frontend

- Single-column form layout.
- Switches for show/hide fields.
- Segmented buttons for author mode.
- Chips for media mode.
- Radio for link mode.
- Text inputs for header/footer with variable chips.

---

### Part 3: QQ (Napcat/OneBot 11)

Goal: integrate OneBot 11 and merged forwarding.

#### Backend

- NapcatPushService:
  - `/send_group_msg` and `/send_private_msg` for normal pushes.
  - JSON array message format.

- Batch Forwarding:
  - `/send_group_forward_msg` or `/send_private_forward_msg`.
  - Build forward nodes per content.

#### Frontend

- Bot onboarding with API URL + token, test connection.
- Targets page listing QQ groups/users.
- Rule subscription management.
- Override render config per target.
- New target wizard with merge forward option.

---

## 3. Roadmap

1. Phase 1: Base
   - Implement NapcatPushService.
   - Add `render_config` to DistributionRule.
2. Phase 2: Queue Enhancements
   - Improve `/queue/reorder`.
   - Frontend drag sorting.
3. Phase 3: Personalized + Batch
   - Telegram dynamic rendering.
   - Merge forward logic.
   - Frontend batch UI.

## 4. Example Snippets

### Distribution Rule Target
```json
{
  "platform": "qq",
  "target_id": "12345678",
  "render_config": {
    "show_media": false,
    "template": "Brief {{title}}\n{{link}}"
  }
}
```

### Batch Push (Pseudo)
```python
async def push_batch(content_ids, target_id):
    nodes = []
    for cid in content_ids:
        content = get_content(cid)
        text = format_digest(content)
        nodes.append({
            "type": "node",
            "data": {
                "name": "VaultStream Bot",
                "uin": BOT_QQ,
                "content": text
            }
        })

    await napcat_client.post("/send_forward_msg", json={
        "group_id": target_id,
        "messages": nodes
    })
```

## Phase 1 - Status Report

- Status: Completed
- Date: 2026-02-09
- Scope: render_config field + Napcat push service + merged forward base logic
- Backend summary:
  - Added render_config to DistributionRule and passed it through push payloads.
  - Added render_config based rendering in text_formatters for Telegram/QQ.
  - Introduced NapcatPushService for QQ messages and merged forward.
  - Distribution engine emits target_meta and merged forward tasks; scheduler can group tasks.
  - Distribution worker supports merged forward tasks and records pushes.
- Notes: Backend only. Frontend UI pending.

---

## Phase 2 & Phase 3 - Status Report

- Status: Completed
- Date: 2026-02-09
- Scope: Queue enhancements + Frontend UI for personalized rendering + Target-level config override

### Backend Enhancements

**New APIs**:
1. `POST /queue/items/{content_id}/push-now` - Immediate push for single item
   - Sets `scheduled_at` to past time (-24h) with `queue_priority=9999`
   - Calls `compact_schedule()` and `trigger_run()` to wake scheduler
   - Publishes `queue_updated` event for frontend refresh

2. `POST /queue/merge-group` - Merge multiple items into one time group
   - Aligns `scheduled_at` for all items to same timestamp
   - Supports custom time or uses earliest existing time
   - Triggers compaction and event publish

**Improvements**:
- `batch-push-now` now triggers scheduler and publishes events
- All comments English-localized for consistency
- Event-driven refresh via SSE event bus

### Frontend Implementation

**New Components**:
1. `RenderConfigEditor` widget
   - Complete render_config editing UI
   - Display control: show_title, show_tags, show_platform_id
   - Mode selectors: author_mode, content_mode, media_mode, link_mode
   - Template text inputs with variable support ({{date}}, {{title}})
   - Reusable in both rule and target dialogs

2. `TargetEditorDialog` widget
   - Standalone target editing dialog
   - Platform selector (Telegram/QQ)
   - Target-level fields: merge_forward, use_author_name, summary
   - Integrated RenderConfigEditor for per-target override
   - Material 3 design aligned with rule dialog

**Model Updates**:
- Added `render_config` field to DistributionRule, DistributionRuleCreate, DistributionRuleUpdate

**Provider Updates**:
- Added `pushNow(contentId)` method
- Added `mergeGroup(contentIds, {scheduledAt?})` method
- Improved soft refresh with data change detection

**UI Enhancements**:
- DistributionRuleDialog: Integrated RenderConfigEditor as expansion tile
- DistributionRuleDialog: Target cards show override indicator (palette icon)
- QueueContentList: Added "Merge Group" button in batch action bar
- QueueContentList: "Push Now" in time menu calls dedicated API
- QueueContentList: Optimistic update for instant UI feedback

### Code Quality

**Strengths**:
- RESTful API design with clear separation of concerns
- Component reusability (RenderConfigEditor used in 2 places)
- Event-driven architecture reduces coupling
- Optimistic updates and debounce for smooth UX
- Comprehensive error handling and user feedback

**Areas for Improvement**:
- Consider using Pydantic/freezed models for RenderConfig and DistributionTarget instead of Map<String, dynamic>
- Standardize render_config format (nested vs flat structure)
- Add inline documentation for merge_forward and use_author_name field usage

### Testing Status

- Manual testing: ✅ Passed
- Integration testing: Pending
- E2E testing: Pending

### Implementation Progress Summary

**Phase 1 (Backend Foundation)** - ✅ 100% Complete
- ✅ render_config field in DistributionRule
- ✅ Napcat push service with OneBot 11 API
- ✅ Batch forward logic in distribution engine

**Phase 2 (Queue Enhancements)** - ✅ 100% Complete
- ✅ Immediate push API (`/queue/items/{id}/push-now`)
- ✅ Scheduler wake-up mechanism (`trigger_run()`)
- ✅ Batch reschedule and merge APIs
- ✅ Event-driven refresh via SSE

**Phase 3 (Frontend Queue Dashboard)** - ✅ 95% Complete
- ✅ Material 3 Expressive design language
- ✅ Responsive layout with LayoutBuilder
- ✅ Drag-and-drop reordering with ReorderableListView
- ✅ Batch selection and operations
- ⚠️ Specialized tablet/landscape optimizations pending

**Phase 4 (Rule Editor & Target Management)** - ⚠️ 85% Complete
- ✅ RenderConfigEditor widget (reusable)
- ✅ TargetEditorDialog for add/edit targets
- ✅ Integrated in DistributionRuleDialog
- ✅ Target-level render config override
- ❌ **Missing: Standalone Target Management Page**
  - Global view of all targets across rules
  - Bulk operations on targets
  - Target health monitoring

### Code Quality Improvements Applied

1. **Backend Type Safety** - ✅ FIXED
   - Created `RenderConfig` Pydantic model with field validation
   - Enhanced `DistributionTarget` schema with all Phase 1-3 fields:
     - `merge_forward`, `use_author_name`, `summary`
     - `render_config` override support
   - Better API documentation through typed schemas

2. **Code Consistency** - ✅ FIXED
   - Standardized English comments in backend API layer
   - Aligned naming conventions across backend/frontend

### Known Issues & Optimization Opportunities

1. **Target Schema Validation**
   - Current: `targets: List[Dict[str, Any]]` for backward compatibility
   - Recommended: Add Pydantic validator to enforce DistributionTarget structure
   - Impact: Better type safety and auto-generated API docs

2. **Render Config Format**
   - Current: Supports both nested `{structure: {...}}` and flat format
   - Recommended: Backend normalize to single format before storage
   - Impact: Simpler frontend logic, reduced edge cases

3. **Responsive Layout**
   - Current: Basic responsive with LayoutBuilder
   - Recommended: Add breakpoint-specific layouts for tablet/desktop
   - Impact: Better UX on large screens with dual-pane layouts

4. **Target Management**
   - Current: Targets managed only within rule dialogs
   - Missing: Global target management page
   - Impact: Hard to audit/manage targets across multiple rules

### Next Steps (Priority Order)

**High Priority - Missing Features**:
1. ✨ **Standalone Target Management Page** (NEW)
   - List all targets across all rules with grouping by platform
   - Show target usage count (how many rules use each target)
   - Bulk enable/disable targets
   - Test connection status for each target
   - Quick edit target render config

2. 🎯 **Render Config Preset Templates** (NEW)
   - Predefined templates: "Minimal", "Standard", "Detailed", "Media-Only"
   - Template picker in RenderConfigEditor
   - Save custom templates
   - Import/export template JSON

3. 📱 **Enhanced Responsive Layouts** (IMPROVEMENT)
   - Tablet landscape: Dual-pane (timeline + preview)
   - Desktop: Three-column (filters | timeline | detail panel)
   - Mobile portrait: Optimized compact cards

**Medium Priority - Developer Experience**:
4. 🔧 **Target Schema Validation** (IMPROVEMENT)
   - Add Pydantic validator to DistributionRuleCreate/Update
   - Enforce DistributionTarget structure in API layer
   - Generate OpenAPI docs from schemas

5. 📚 **API Documentation** (NEW)
   - OpenAPI/Swagger for new queue endpoints
   - Interactive API testing interface
   - Code examples for common operations

6. 🧪 **Testing Coverage** (NEW)
   - Integration tests for queue batch operations
   - E2E tests for render config override behavior
   - Frontend widget tests for RenderConfigEditor

**Low Priority - Polish**:
7. 🎨 **UI/UX Enhancements**
   - Loading skeletons for queue items
   - Animations for batch operations
   - Haptic feedback on mobile drag-and-drop

8. ⚡ **Performance Optimizations**
   - Virtualized list for large queues (1000+ items)
   - Incremental updates instead of full refresh
   - Client-side filtering/sorting

### Metrics & Success Criteria

**Completed**:
- ✅ Backend APIs: 100% (all endpoints implemented)
- ✅ Core UI Components: 95% (missing standalone target page)
- ✅ Type Safety: Improved (Pydantic schemas added)

**Target Metrics for v1.0**:
- [ ] Test Coverage: >80% for queue/distribution modules
- [ ] Response Time: <200ms for queue operations
- [ ] UI Performance: 60fps on drag operations
- [ ] Feature Completeness: 100% of Phase 1-4 features
