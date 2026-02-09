# Review, Queue, and Push Upgrade Design

This document reviews the current Review, Queue, and Push behavior and proposes upgrades for queue management, personalized push configuration, and QQ (Napcat) support.

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

## Phase 1 - Temporary Status Report

- Status: Completed
- Date: 2026-02-09
- Scope: render_config field + Napcat push service + merged forward base logic
- Backend summary:
  - Added render_config to DistributionRule and passed it through push payloads.
  - Added render_config based rendering in text_formatters for Telegram/QQ.
  - Introduced NapcatPushService for QQ messages and merged forward.
  - Distribution engine emits target_meta and merged forward tasks; scheduler can group tasks.
  - Distribution worker supports merged forward tasks and records pushes.
- Notes: No frontend changes yet. Phase 2 and Phase 3 pending.
