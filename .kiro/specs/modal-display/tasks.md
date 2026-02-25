# Implementation Plan

- [x] 1. (P) Add `data-media-type` to SSR-rendered directory cards
  - In `directory.ecr`, add `data-media-type="<%= entry.media_type %>"` attribute to every non-directory `<a class="card">` element
  - Directory cards (`card--dir`) must not receive this attribute
  - Verify the attribute renders correctly for image, video, pdf, and unknown entries using the existing test-media fixtures
  - _Requirements: 1.1, 1.3, 6.1_

- [x] 2. (P) Add overlay CSS to the stylesheet
  - Add a full-screen fixed-position backdrop (`#overlay`) with a dark semi-transparent background and `z-index` above all grid content; hidden by default
  - Center the image element inside the overlay with `max-width: 100%` and `max-height: 90vh` to avoid overflow on small screens
  - Style a close button (`×`) positioned in the top-right corner of the overlay
  - Style prev and next navigation buttons on the left and right sides; include a visually distinct disabled state
  - Style a filename label at the bottom of the overlay
  - Add a `body.overlay-open` class rule that sets `overflow: hidden` to prevent background scroll
  - _Requirements: 1.2, 1.4, 1.5, 1.7_

- [x] 3. Initialize overlay DOM and intercept card clicks
- [x] 3.1 Inject overlay HTML and extend `buildCard` for media-type
  - At the end of the `app.js` IIFE, create the overlay element (`div#overlay`) containing: a backdrop div, an `img#overlay-img`, a `p#overlay-name`, a `button#overlay-close`, a `button#overlay-prev`, and a `button#overlay-next`; append it to `document.body`
  - In `buildCard(e)`, after setting `a.className`, also set `a.dataset.mediaType = e.media_type` for non-directory entries
  - _Requirements: 1.1, 1.2, 1.4, 1.5_

- [x] 3.2 Attach click handler to the directory grid
  - Add a single delegated `click` event listener on the `grid` element that reads `data-media-type` from the clicked card
  - For `image` cards: call `preventDefault()` and proceed to open the overlay
  - For `video` cards: call `preventDefault()` and open the card's `href` in a new tab via `window.open(href, '_blank')`
  - For `pdf` and unrecognized media types: allow default `<a>` navigation to proceed (do not call `preventDefault()`)
  - Confirm that the existing `/view/*` SSR page is still reachable by direct URL (no server-side changes required)
  - _Requirements: 1.1, 1.3, 5.4, 6.1, 6.2_

- [x] 4. Implement overlay open and close lifecycle
- [x] 4.1 Implement `openOverlay(card)`
  - Record `window.scrollY` into `savedScrollY` before any DOM changes
  - Add the `overlay-open` class to `document.body` to lock background scroll
  - Clear `img#overlay-img`'s `src`, then set it to the card's raw image URL (derived by replacing the `/view/` prefix in `card.href` with `/raw/`)
  - Set `p#overlay-name`'s text content to the card's filename (from its `.name` span)
  - Store a reference to the card in `currentCard`
  - Remove the `hidden` attribute from `#overlay` to display it
  - Push the card's `/view/[path]` URL to the browser history via `history.pushState`
  - Call `updateNavButtons()` to set initial button states
  - _Requirements: 1.2, 1.4, 3.1, 3.3, 5.1, 8.3_

- [x] 4.2 Implement `closeOverlay()` and the `popstate` handler
  - In `closeOverlay()`: set `overlayOpen` to false, add `hidden` back to `#overlay`, clear `img#overlay-img.src` to release memory, remove `overlay-open` from `document.body`, and call `window.scrollTo(0, savedScrollY)` to restore position
  - When `closeOverlay()` is triggered by a button or keyboard action (not by `popstate`), call `history.back()` to pop the pushed history entry
  - Add a `popstate` listener on `window`; when the overlay is open and `popstate` fires, call `closeOverlay()` without calling `history.back()` a second time
  - Wire the `#overlay-close` button's `click` event to call `closeOverlay()`
  - Wire clicks on the `#overlay` backdrop (outside the content area) to call `closeOverlay()`
  - _Requirements: 1.6, 1.7, 3.2, 5.3, 8.1_

- [ ] 5. Implement sort-aware in-overlay image navigation
- [ ] 5.1 Implement `getImageCards()` and `showFile(card)`
  - `getImageCards()` queries `grid.querySelectorAll('.card[data-media-type="image"]')` live each time it is called, ensuring cards added by `loadMore()` are included automatically
  - `showFile(card)` clears `img#overlay-img.src`, updates `currentCard`, sets the new `src` to the raw image URL, updates the filename label, and calls `history.replaceState` with the new file's `/view/[path]` URL
  - _Requirements: 2.1, 2.4, 5.2, 8.2, 8.3_

- [ ] 5.2 Implement `updateNavButtons()` and batch extension on last card
  - `updateNavButtons()` computes `currentIdx` as the position of `currentCard` in the live `getImageCards()` result, then sets `#overlay-prev` disabled when `currentIdx === 0`, and `#overlay-next` disabled when `currentIdx` is the last index and `exhausted` is true
  - Wire `#overlay-prev` click to call `showFile(imageCards[currentIdx - 1])` when not disabled
  - Wire `#overlay-next` click: when `currentIdx < imageCards.length - 1`, call `showFile(imageCards[currentIdx + 1])`; when at the last loaded card and `!exhausted`, disable the button, call `loadMore()`, and after the fetch completes re-query image cards and navigate to the newly added next card
  - _Requirements: 2.2, 2.3, 2.5, 2.6, 2.7_

- [ ] 6. (P) Add keyboard navigation for the overlay
  - Add a `keydown` listener on `document` that acts only when the overlay is open (`overlayOpen === true`)
  - `ArrowRight` key: call `#overlay-next` click logic (navigate to next image)
  - `ArrowLeft` key: call `#overlay-prev` click logic (navigate to previous image)
  - `Escape` key: call `closeOverlay()`
  - Prevent default browser action for all three keys while the overlay is open to avoid unwanted page scroll
  - Can be implemented concurrently with task 7; both tasks depend on tasks 4 and 5 being complete
  - _Requirements: 7.1, 7.2, 7.3_

- [ ] 7. (P) Add swipe gesture navigation for the overlay
  - Add `touchstart` listener on `#overlay` to record `touchStartX` and `touchStartY`
  - Add `touchend` listener on `#overlay`; compute `deltaX = touchEndX - touchStartX` and `deltaY = touchEndY - touchStartY`
  - Treat as a swipe only when `Math.abs(deltaX) >= 50` and `Math.abs(deltaX) > Math.abs(deltaY)` (horizontal dominates, no interference with vertical scroll)
  - Negative `deltaX` (left swipe): invoke next-image navigation; positive `deltaX` (right swipe): invoke previous-image navigation
  - If no next or previous is available in the swipe direction, take no action
  - Can be implemented concurrently with task 6; both tasks depend on tasks 4 and 5 being complete
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_
