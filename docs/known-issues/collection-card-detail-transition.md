# Known Issue: Collection Card to Detail Transition Still Lands on a Blank Target

**Status**: partially fixed on 2026-06-06; current code still needs a real detail-side Hero target  
**Area**: `frontend/lib/features/collection/`  
**Observed**: the transition now has a card-like flight shuttle, but the loaded detail page still anchors the Hero to an empty full-page surface.

## Current State

The old implementation animated an empty `card-bg-*` background. That part has been improved:

- `collection_card_preview.dart` now defines `collectionCardHeroTag(int contentId) => 'card-shell-$contentId'`.
- `ContentCard` wraps `CollectionCardPreview` in a `Hero`.
- The route passes a `ShareCard` preview through `GoRouter.extra`.
- The loading state in `ContentDetailPage` can render the same card preview while detail data is loading.
- The route transition has been softened to a near-opaque fade.

This means the in-flight layer is no longer just a blank background.

## Remaining Problem

The loaded detail page still contains this target Hero:

```dart
Hero(
  tag: collectionCardHeroTag(widget.contentId),
  flightShuttleBuilder: collectionCardFlightShuttleBuilder(...),
  child: Material(
    color: colorScheme.surface,
    child: const SizedBox.expand(),
  ),
)
```

So the destination Hero is still an empty full-screen surface. The shuttle can look like a real card during the flight, but it does not morph into a real first-viewport detail header. This matches the user-visible symptom: the app appears to animate between two blank boards with a temporary card-like overlay.

## Required Fix

1. Replace the loaded detail target Hero with a real detail-side header, not `SizedBox.expand()`.
2. The target should include stable identity elements shared with the card: cover/fallback, title, author, platform, tags and base surface.
3. Keep the loading preview until detail data is ready, then transition from preview to the real header.
4. Ensure article, gallery, video and text-only layouts all expose a stable target region.
5. Keep route-level fade minimal or delay it until the Hero has established continuity.

## Validation

After implementation, verify with widget, route, and layout tests where possible; manual visual checks are optional release evidence, not the default agent exit condition:

- card -> detail and detail -> card
- desktop and mobile portrait
- slow detail loading
- missing cover image
- article, gallery, video and text-only content
- returning after SSE list updates or filter changes

Latest historical automated checks may still pass because they only verify Hero presence and route behavior; they do not prove that the target Hero is visually meaningful.
