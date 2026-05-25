# Known Issue: Collection Card to Detail Transition Shows Blank Surfaces

**Status**: initial fix implemented on 2026-05-25; visual verification pending  
**Area**: `frontend/lib/features/collection/`  
**Observed**: the card-to-detail transition moves geometrically, but the moving surface is visually empty during both forward and back navigation.

## Symptom

Opening a collection item should feel like the card expands into the detail page and collapses back into the same card. The current animation has position/size movement, but the transition layer mostly contains an empty surface:

- Card -> detail: the card background moves, but the card content/cover/title do not travel with it.
- Detail -> card: the destination card area can appear blank until the list repaints.

## Current Implementation

Relevant code:

- `content_card.dart`: card background Hero uses `tag: 'card-bg-${content.id}'`.
- `content_card.dart`: cover image Hero uses `tag: 'content-image-${content.id}'`.
- `content_detail_page.dart`: detail background Hero uses `tag: 'card-bg-${widget.contentId}'`.
- `content_detail_page.dart`: loading state is a separate Scaffold with no matching Hero.
- `app_router.dart`: detail route also applies a page-level slide/fade transition.

The shared element that always exists is the background Hero. Its child is only a decorated container on the card side and a full-screen surface on the detail side. That explains why movement works but the visible content does not feel continuous.

## Root Causes

1. **Wrong primary shared element**

   The `card-bg-*` Hero only animates the background shell. The actual card content is outside that Hero. Flutter is doing what it was asked to do: morph an empty background.

2. **Asymmetric Hero trees**

   The card side has background, cover image, author, title, tags, footer, and semantic badge. The detail side only has a background Hero at the page root. The cover image may have a matching `content-image-*` Hero in some detail layouts, but not all content types expose it in the same position or at initial load.

3. **Loading route has no shared visual**

   While `contentDetailProvider` is loading, the detail page returns `_buildLoadingState()`, which does not contain `card-bg-*` or `content-image-*`. If the route lands in loading state during the Hero flight, the target subtree is effectively missing.

4. **Page-level transition competes with Hero**

   `CustomTransitionPage` wraps the detail page in slide/fade. The whole page fades while Hero layers are also trying to create continuity. This can make the non-Hero page content disappear at exactly the time the shared element should carry the visual identity.

5. **Back navigation depends on list state**

   On pop, Flutter needs the original card Hero to still be mounted. Filtering, SSE invalidation, masonry relayout, scroll position changes, or image cache delay can leave the destination card visually incomplete during the return flight.

## Recommended Fix

### 1. Promote the full card shell to the shared Hero

Instead of animating only the background, wrap a stable card preview subtree in one Hero:

- fixed clipping wrapper
- background decoration
- cover thumbnail if present
- title/author metadata enough to keep identity
- no hover-only scale/shadow changes during flight

Use `Hero.flightShuttleBuilder` so the in-flight widget is a deterministic preview, not whichever source/destination subtree happens to be active.

### 2. Keep the destination Hero present during loading

Pass a lightweight `ShareCard` preview through route `extra` when pushing the detail page. Render that preview in the loading state with the same `card-shell-*` Hero tag. After detail data arrives, crossfade from preview to real detail content.

Preferred route push shape:

```dart
context.push(
  '/collection/${item.id}$colorParam',
  extra: item,
);
```

Then `ContentDetailPage` accepts `ShareCard? preview`.

### 3. Split shared layers deliberately

Use two optional shared elements:

- `card-shell-{id}`: the full card preview/surface, always available.
- `content-image-{id}`: the cover/media item, only when both source and destination have a stable image.

Do not require every layout to support image Hero. For text-only/article layouts, the shell Hero is enough.

### 4. Reduce page transition during Hero flight

For the collection detail route, either:

- remove the route-level fade/slide and let Hero carry the transition, or
- keep only a very subtle fade for non-Hero content after the Hero starts.

The current whole-page slide/fade makes the shared element look like it is moving over an empty page.

### 5. Freeze card visual state while navigating

Disable hover scale/shadow changes for the tapped card once navigation starts, and keep stable dimensions:

- same border radius on source and in-flight shell
- `clipBehavior` / `ClipRRect` around the Hero child
- stable aspect ratio
- no delayed list fade-in animation on the returning card

### 6. Validate return path

After implementation, verify:

- card -> detail for article, gallery, video, and text-only items
- detail -> card with browser/app back
- return after scroll position changes
- return after SSE list update
- image missing/error fallback
- slow detail loading

## Suggested Implementation Order

1. Extract `CollectionCardPreview` from `ContentCard` so the same preview can be reused by the card, Hero flight shuttle, and detail loading state.
2. Change `card-bg-*` to `card-shell-*` and make it wrap the real preview surface.
3. Pass `ShareCard` through GoRouter `extra`.
4. Add a preview-aware loading state in `ContentDetailPage`.
5. Remove or soften the collection detail route page fade/slide.
6. Add a widget/golden-style smoke test for the loading state containing the expected Hero tags.

## Implemented Changes

- Added `CollectionCardPreview` so the grid card, Hero flight shuttle, and detail loading state share the same visual subtree.
- Replaced the primary card Hero from `card-bg-{id}` to `card-shell-{id}`.
- Passed `ShareCard` through GoRouter `extra` when opening a collection detail route.
- Added a preview-aware loading state in `ContentDetailPage` so slow detail fetches still have a matching target Hero.
- Added `flightShuttleBuilder` on the grid card Hero so push uses the source card appearance and pop uses the destination card appearance.
- Softened the detail route transition from slide/fade to a near-opaque fade so it does not fight the Hero motion.
- Removed delayed per-card list entry animation from `ContentCard`, reducing blank/late repaint risk on back navigation.

Remaining validation:

- Inspect the animation on desktop/web and mobile widths.
- Confirm gallery/video/article/text-only items all have acceptable forward and back transitions.
- Confirm SSE list refresh during detail view does not remove the returning card before pop finishes.
