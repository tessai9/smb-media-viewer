# Requirements Document

## Introduction

The modal-display feature transforms how image files are viewed in the SMB Media Viewer. Instead of navigating to a separate `/view/*` page, clicking an image file opens a full-screen in-page overlay (modal/lightbox) while the directory listing stays underneath. This resolves three UX problems: (1) sort state is lost when the user navigates away from the list, (2) scroll position is lost when returning from the viewer, and (3) swipe-based file navigation is impractical across full-page transitions on mobile. Video files open in a new browser tab to isolate memory usage and leverage native browser video playback. PDF files continue to use the existing SSR viewer page due to embedded-PDF limitations on older mobile browsers.

## Requirements

### Requirement 1: In-Page Image Overlay

**Objective:** As a user, I want image files to open in an overlay on the current list page, so that I can view images without losing my position in the directory.

#### Acceptance Criteria
1. When a file card for an image is clicked in the directory grid, the Media Viewer shall open a full-screen overlay displaying the image without navigating away from the list page.
2. The Media Viewer shall display image files in the overlay using an `<img>` element sourced from `/raw/[path]`.
3. When a file card for a video is clicked in the directory grid, the Media Viewer shall open the file's `/view/[path]` page in a new browser tab.
4. The Media Viewer shall display the filename of the currently viewed image within the overlay.
5. The Media Viewer shall provide a clearly visible close button in the overlay.
6. When the close button is activated, the Media Viewer shall dismiss the overlay and reveal the directory listing.
7. While the overlay is open, the Media Viewer shall prevent background scroll of the directory listing.

---

### Requirement 2: Sort-Aware Previous/Next Navigation

**Objective:** As a user, I want previous/next navigation in the overlay to follow the current sort order, so that sequential browsing matches what I see in the list.

#### Acceptance Criteria
1. The Media Viewer shall determine the previous and next file relative to the currently displayed file based on the active sort key (name, mtime, or ctime) and sort direction (asc or desc) reflected in the directory grid's state.
2. When the previous button is activated, the Media Viewer shall load and display the preceding file in the current sort order.
3. When the next button is activated, the Media Viewer shall load and display the following file in the current sort order.
4. While navigating prev/next, the Media Viewer shall update the overlay content and filename without closing and reopening the overlay.
5. The Media Viewer shall disable (or hide) the previous button when the currently displayed file is the first file in the loaded list.
6. The Media Viewer shall disable (or hide) the next button when the currently displayed file is the last file in the loaded list and no more files remain to be fetched.
7. When the user reaches the last loaded file and additional files remain on the server, the Media Viewer shall fetch the next batch from `/api/files/*` and extend the available navigation range before enabling the next button.

---

### Requirement 3: Scroll Position Preservation

**Objective:** As a user, I want to return to my exact scroll position in the directory listing after closing the overlay, so that I do not have to scroll back to where I was.

#### Acceptance Criteria
1. When the overlay is opened, the Media Viewer shall record the current vertical scroll position of the page.
2. When the overlay is closed, the Media Viewer shall restore the page to the recorded scroll position.
3. The directory listing DOM (grid and all loaded cards) shall remain intact in memory while the overlay is open.

---

### Requirement 4: Swipe Gesture Navigation

**Objective:** As a mobile user, I want to swipe horizontally to navigate between files, so that I can browse files naturally with one hand.

#### Acceptance Criteria
1. While the overlay is open on a touch device, the Media Viewer shall detect horizontal touch swipe gestures with a horizontal displacement of at least 50 pixels.
2. When a leftward swipe is detected, the Media Viewer shall navigate to the next file.
3. When a rightward swipe is detected, the Media Viewer shall navigate to the previous file.
4. The swipe detection shall not interfere with native vertical page scrolling.
5. If no next or previous file is available in the swipe direction, the Media Viewer shall take no navigation action.

---

### Requirement 5: Browser History and URL Integration

**Objective:** As a user, I want the browser URL to reflect the currently viewed file, so that I can bookmark or share a direct link and use the browser back button to close the overlay.

#### Acceptance Criteria
1. When the overlay is opened, the Media Viewer shall push the corresponding `/view/[encoded-path]` URL to the browser history stack using the History API (`history.pushState`).
2. When navigating between files within the overlay (prev/next or swipe), the Media Viewer shall replace the current history entry with the new file's URL using `history.replaceState`.
3. When the user activates the browser back button while the overlay is open, the Media Viewer shall close the overlay and restore the list page URL without a full page reload.
4. When a user navigates directly to a `/view/[path]` URL (e.g., from a bookmark or shared link), the Media Viewer shall serve the existing SSR viewer page as a standalone fallback.

---

### Requirement 6: PDF File Handling

**Objective:** As a user, I want PDF files to open in the most compatible way for my browser, so that I can read document content without a degraded experience.

#### Acceptance Criteria
1. When a PDF file card is clicked, the Media Viewer shall navigate to the existing SSR `/view/[path]` page rather than opening an overlay.
2. The existing SSR viewer page for PDF files shall remain fully functional and unmodified.

---

### Requirement 7: Keyboard Navigation

**Objective:** As a desktop user, I want to navigate and dismiss the overlay using keyboard shortcuts, so that I can browse efficiently without a mouse.

#### Acceptance Criteria
1. While the overlay is open, the Media Viewer shall respond to the right arrow key by navigating to the next file.
2. While the overlay is open, the Media Viewer shall respond to the left arrow key by navigating to the previous file.
3. While the overlay is open, the Media Viewer shall respond to the Escape key by closing the overlay.

---

### Requirement 8: Resource and Memory Management

**Objective:** As a system operator, I want media resources to be released when no longer displayed, so that the client remains lightweight on older smartphones with limited memory.

#### Acceptance Criteria
1. When the overlay is closed, the Media Viewer shall clear the image element's `src` attribute to release the image from memory.
2. When a different image is loaded into the overlay, the Media Viewer shall clear the previous image's `src` before setting the new one.
3. The Media Viewer shall not begin loading full-resolution image content until the overlay is opened for that file (no background preloading of raw assets).
