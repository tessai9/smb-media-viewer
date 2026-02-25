# Implementation Plan

- [x] 1. Implement natural sort comparison in the file browser
- [x] 1.1 Build the segment-based filename comparison helper
  - Add a private helper to the file browser module that accepts two pre-downcased filename strings and returns a negative, zero, or positive integer indicating their natural sort order
  - Split each string into alternating non-digit and digit segments by scanning character by character; only ASCII digit characters ('0'–'9') are classified as digits — all other characters including multibyte codepoints belong to text segments
  - Compare text segments using standard string ordering (case-insensitive treatment is already applied by the caller via pre-downcase)
  - Compare digit segments by parsing each run as an unsigned 64-bit integer so that `2` < `10` rather than `10` < `2`; use `0` as fallback for overflow (practically impossible with real filenames)
  - When all segments compared so far are equal, the filename with fewer remaining characters is ordered first
  - Return `0` for two strings that are identical under this comparison (supports stable sort)
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2, 3.1, 3.3, 3.4_

- [x] 1.2 Apply the new comparison helper to the Name sort path
  - In the file browser's internal sort method, replace the single expression that compares names lexicographically with a call to the new helper, passing both names pre-downcased (consistent with the existing pattern)
  - Leave the Mtime and Ctime sort branches completely unchanged
  - Leave the descending-order negation logic unchanged — it wraps the comparison result and already works correctly with any comparator
  - Leave the directory-before-file grouping and the offset/limit pagination slice unchanged
  - _Requirements: 1.2, 1.3, 3.2, 4.1, 4.2, 4.3, 4.4_

- [ ] 2. Cover natural sort behavior with tests
- [ ] 2.1 Write tests for core numeric ordering and multi-segment filenames
  - Create a new test directory helper that contains files named to exercise numeric ordering, e.g. `image1.jpg`, `image2.jpg`, `image10.jpg`
  - Assert that ascending Name sort produces the order `image1.jpg → image2.jpg → image10.jpg` (not `image1.jpg → image10.jpg → image2.jpg`)
  - Assert that descending Name sort produces the reverse order `image10.jpg → image2.jpg → image1.jpg`
  - Add a test for filenames with multiple numeric segments (e.g. `ep1part2.mp4` < `ep1part10.mp4` < `ep2part1.mp4`) to verify all segment positions are evaluated
  - Confirm that purely alphabetical filenames (no digits) continue to sort in the same order as before — natural sort must not regress lexicographic behavior for non-numeric names
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 2.1, 2.2_

- [ ] 2.2 Write tests for edge cases including leading zeros, special characters, and multibyte filenames
  - Assert that filenames differing only in leading zeros sort numerically: `file01.jpg` and `file1.jpg` compare equal or consistently (both parse as integer `1`)
  - Assert that a filename starting with an underscore (e.g. `_note.jpg`) sorts before a filename starting with a lowercase letter (e.g. `anote.jpg`), matching ASCII code-point order for the underscore character (95 < 97)
  - Assert that filenames with a Japanese (multibyte) text prefix followed by a number sort by the numeric portion: `画像1.jpg → 画像2.jpg → 画像10.jpg`
  - Confirm that all previously existing sort tests in the sort spec file still pass without modification — Mtime, Ctime, directory-before-file ordering, and pagination slice tests must be unaffected
  - _Requirements: 1.4, 3.1, 3.2, 3.3, 3.4, 4.1, 4.2, 4.3, 4.4, 5.1, 5.2, 5.3_
