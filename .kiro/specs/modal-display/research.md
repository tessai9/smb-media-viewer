# Research & Design Decisions

---
**Feature**: `modal-display`
**Discovery Scope**: Extension — modifying existing frontend with no backend changes
**Key Findings**:
- `media_type` is already present in the `/api/files/*` JSON response (`FileEntry` is `JSON::Serializable`); `buildCard()` already receives it — just needs to be written to a `data-media-type` attribute.
- SSR-rendered cards (first batch from ECR) do not currently carry `data-media-type`; one attribute must be added to `directory.ecr`.
- No new server routes, Crystal code, or shards are required. The overlay is entirely a frontend addition.
- `loadMore()` already exists and handles batch fetching; the overlay controller must call it programmatically when the user navigates to the last loaded image.

---

## Research Log

### Existing Card Structure
- **Context**: Need to understand how to identify image cards vs video/dir cards in the DOM.
- **Findings**:
  - All non-directory cards: `<a class="card" href="/view/encoded-path"><img ...><span class="name">...</span></a>`
  - Directory cards: `<a class="card card--dir" href="/browse/...">`
  - Image and video cards share the same DOM shape — currently indistinguishable by DOM alone.
- **Implications**: Must add `data-media-type` to cards (both SSR and JS-built) so the overlay controller can filter image-only cards for in-modal navigation.

### Raw Image URL Derivation
- **Context**: The overlay needs to load the full-resolution image. Cards link to `/view/path`; full images are served from `/raw/path`.
- **Findings**: The path segment is identical; only the route prefix differs. `rawUrl = card.href.replace('/view/', '/raw/')` is safe because `/view/` is always the prefix of non-dir card hrefs.
- **Implications**: No additional data attribute required to store the raw URL.

### `media_type` in JSON Payload
- **Context**: Verify that `media_type` field is present in `/api/files/*` JSON.
- **Findings**: `FileEntry` in `file_browser.cr` is `JSON::Serializable` and includes `media_type : String`. Values: `"image"`, `"video"`, `"pdf"`, `"unknown"`.
- **Implications**: `buildCard(e)` can write `e.media_type` to `card.dataset.mediaType` with no server changes.

### `loadMore()` Integration
- **Context**: Overlay navigation must extend past the last loaded item.
- **Findings**: `loadMore()` uses a `busy` flag and updates `grid.dataset.offset`. It is async (fetch-based) with no Promise return; the `busy` flag indicates completion.
- **Implications**: The overlay controller can call `loadMore()` when near the end; it should disable the next button while `busy` is true and re-check card list after load completes (via a small completion callback or re-query after fetch).

### History API Compatibility
- **Context**: `history.pushState` / `replaceState` needed for URL management.
- **Findings**: Supported in all target browsers (modern mobile + older Android ≥ 4.0, iOS ≥ 5.0). No polyfill required.
- **Implications**: Safe to use directly.

### JS Size Budget
- **Context**: Steering specifies JS ≤ 4 KB. Current `app.js` is ~1.8 KB (75 lines, compact style).
- **Findings**: The overlay controller adds ~100 lines of compact JS. Estimated total: ~175 lines / ~4–5 KB unminified, ~3 KB minified. Acceptable if implementation follows the same compact style as existing code (short variable names, no comments, no whitespace).
- **Implications**: Implementation must match the existing terse coding style. No JS framework or utility library may be introduced.

---

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Decision |
|--------|-------------|-----------|---------------------|----------|
| Overlay / Lightbox (in-page) | Inject overlay div; intercept card clicks; manage state in JS | Scroll preserved naturally; sort state preserved; swipe easy | JS size increase; must handle history API carefully | **Selected** |
| Full-page navigation (status quo) | Keep `/view/*` for all types | Zero JS change | Scroll lost; sort lost; no swipe | Rejected for images |
| SPA routing | Client-side router replacing ECR SSR | Full control | Breaks steering constraint (no SPA framework) | Rejected |

---

## Design Decisions

### Decision: Single `app.js` File (No New File)
- **Context**: Should the overlay controller be a separate JS file?
- **Alternatives**:
  1. Separate `overlay.js` served via `<script>` tag in layout
  2. Extend existing `app.js` IIFE
- **Selected Approach**: Extend `app.js`. The overlay controller shares `grid`, `loadMore`, `busy`, `exhausted`, and `encodePath` — all currently scoped inside the IIFE. Extracting would require exposing these or duplicating them.
- **Rationale**: Single file reduces HTTP requests and keeps related state co-located. Consistent with steering's "minimal dependencies" philosophy.
- **Trade-offs**: `app.js` grows. Mitigated by compact coding style.

### Decision: `data-media-type` on Card Elements
- **Context**: Overlay must distinguish image/video/pdf/dir cards.
- **Alternatives**:
  1. Parse filename extension from `href` in JS
  2. Add `data-media-type` attribute
- **Selected Approach**: `data-media-type` attribute on `<a class="card">`. Set in `directory.ecr` (SSR) and `buildCard()` (JS).
- **Rationale**: Clean, declarative, maintainable. Avoids re-implementing MIME logic in JS.
- **Follow-up**: Verify ECR template change doesn't affect any existing tests.

### Decision: Video Cards Open `/view/*` in New Tab
- **Context**: Video in modal is resource-heavy and behaviorally complex on old iOS/Android.
- **Selected Approach**: `window.open(card.href, '_blank')` on click for `data-media-type="video"` cards.
- **Rationale**: Isolates video memory to a new tab; leverages the existing SSR viewer with Range-request support. Zero additional complexity.

### Decision: Derive Raw URL from Card `href`
- **Context**: Need full-res image URL for overlay `<img src>`.
- **Selected Approach**: `card.href.replace('/view/', '/raw/')` — no extra data attribute.
- **Rationale**: The relationship is structural (same path, different route prefix); derived value is always correct.

### Decision: Dynamic `getImageCards()` Query (No Snapshot)
- **Context**: `fileCards` list grows as infinite scroll loads more batches. A snapshot taken at overlay open would go stale.
- **Selected Approach**: Always query `grid.querySelectorAll('.card[data-media-type="image"]')` live. Store index only.
- **Rationale**: DOM is the source of truth; live query stays consistent with `loadMore` additions.

---

## Risks & Mitigations

- **JS size exceeds 4 KB unminified** — Mitigate by following the same compact style as existing code; evaluate at implementation.
- **`loadMore` timing on last-card navigation** — Disable next button while `busy === true`; re-enable after load completes. Prevents double fetch.
- **`popstate` conflicts with other uses** — The app has no other `popstate` listeners currently; risk is low.
- **Old iOS Safari `history.pushState` edge cases** — pushState is supported since iOS 5; no mitigation needed.
- **Backdrop click vs. swipe ambiguity** — A `touchend` with large movement should not also trigger backdrop-close; use a movement threshold check before deciding to close.
