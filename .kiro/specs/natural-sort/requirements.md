# Requirements Document

## Project Description (Input)
natural-sort

## Introduction

The file browser currently sorts filenames using plain lexicographic (dictionary) order, which causes filenames containing numbers to sort incorrectly — for example, `image10.png` appears before `image2.png`. This feature replaces the lexicographic name sort with **natural sort**: numeric substrings within filenames are compared as integers, while non-numeric substrings are compared as case-insensitive text. All other sort keys (mtime, ctime) and the directory-before-file grouping remain unchanged.

## Requirements

### Requirement 1: Numeric Segments Sorted as Integers

**Objective:** As a user browsing a media directory, I want filenames with embedded numbers to appear in numeric order, so that `image2.png` comes before `image10.png` rather than after it.

#### Acceptance Criteria

1. When the sort key is `Name`, the File Browser shall split each filename into alternating non-digit and digit segments and compare digit segments as non-negative integers.
2. When two filenames share the same non-digit prefix and differ only in a numeric segment, the File Browser shall order the entry with the smaller numeric value first in ascending sort.
3. When two filenames share the same non-digit prefix and differ only in a numeric segment, the File Browser shall order the entry with the larger numeric value first in descending sort.
4. The File Browser shall treat a filename that contains no digits as a single non-digit segment and compare it using case-insensitive Unicode text ordering (identical to current behavior for pure-alphabetical names).

---

### Requirement 2: Multi-Segment Numeric Filenames

**Objective:** As a user, I want filenames with multiple numeric segments (e.g., `ep1part2.mp4`) to sort correctly across all numeric positions, so that the full name is evaluated naturally end-to-end.

#### Acceptance Criteria

1. When two filenames share an equal prefix up to the first differing segment, the File Browser shall continue comparing subsequent segments (alternating text and numeric) until a difference is found.
2. When all segments of a shorter filename are equal to the leading segments of a longer filename, the File Browser shall order the shorter filename first.

---

### Requirement 3: Non-Numeric and Multibyte Character Handling

**Objective:** As a user, I want special characters and multibyte (e.g., Japanese) characters in filenames to sort predictably, so that the ordering is deterministic and consistent.

#### Acceptance Criteria

1. The File Browser shall treat any character that is not an ASCII digit (`0`–`9`) as a non-digit character belonging to a text segment.
2. When comparing text segments, the File Browser shall apply case-insensitive comparison (lowercase fold on ASCII letters) before comparing by Unicode code-point order.
3. The File Browser shall sort filenames whose text segments consist entirely of multibyte characters (e.g., `画像1.png`) in Unicode code-point order for the text portion and as integers for the numeric portion.
4. The File Browser shall sort filenames beginning with special ASCII punctuation (e.g., `_`, `(`, `)`) according to their ASCII code-point values, which places them before lowercase ASCII letters.

---

### Requirement 4: Scope — Name Sort Only; Existing Ordering Rules Preserved

**Objective:** As a developer, I want natural sort to apply exclusively to name-based sorting and to leave all other ordering rules intact, so that no existing behavior is broken.

#### Acceptance Criteria

1. The File Browser shall apply natural sort only when the active sort key is `Name`; `Mtime` and `Ctime` sort keys shall remain unaffected.
2. The File Browser shall continue to place all directories before all files regardless of the sort key or direction.
3. When the sort direction is `Desc`, the File Browser shall reverse natural sort order (largest numeric segment first) symmetrically.
4. The File Browser shall treat `offset` and `limit` pagination as a post-sort slice, applied after natural sort ordering is determined.

---

### Requirement 5: Consistency Across All Endpoints

**Objective:** As a user, I want the file order to be identical whether the page is loaded for the first time (SSR) or via the JSON API for infinite scroll, so that the displayed sequence never changes as more items load.

#### Acceptance Criteria

1. When the `GET /browse/*path` route renders the initial SSR HTML batch, the File Browser shall use natural sort for the Name key.
2. When the `GET /api/files/*path` endpoint returns JSON for subsequent infinite-scroll batches, the File Browser shall use the same natural sort logic as the SSR route.
3. The File Browser shall produce a stable sort: two entries that compare equal under natural sort (identical filename) shall maintain a consistent relative order across repeated calls.
