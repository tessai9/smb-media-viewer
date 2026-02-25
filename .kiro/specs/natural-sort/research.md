# Research & Design Decisions

---
**Purpose**: Capture discovery findings, architectural investigations, and rationale that inform the technical design.

---

## Summary

- **Feature**: `natural-sort`
- **Discovery Scope**: Extension (existing system)
- **Key Findings**:
  - The change is confined to a single private comparator inside `FileBrowser.scan_entries` — no HTTP layer, no new files, no new shards required.
  - All four route handlers (`GET /browse/`, `GET /browse/*path`, `GET /api/files/`, `GET /api/files/*path`) already share the same `FileBrowser.list_entries` call path, so fixing the comparator at the service layer satisfies Requirement 5 automatically.
  - Crystal's `each_char` iterates Unicode codepoints (not bytes), which means multibyte characters are handled correctly by default — a digit check on `('0'..'9').includes?(c)` will never spuriously match a multibyte character's byte fragment.

---

## Research Log

### Natural Sort: External Libraries vs. In-house Implementation

- **Context**: Determine whether to use a Crystal shard or implement the algorithm in-house.
- **Sources Consulted**: Crystal shard registry (shards.info), project CLAUDE.md dependency policy ("kemal is the only Crystal shard dependency").
- **Findings**:
  - No widely-adopted Crystal natural-sort shard exists with active maintenance.
  - The project's steering explicitly limits shards to `kemal` only.
  - The algorithm is straightforward: split filename into alternating text/digit segments, compare text segments as strings and digit segments as integers.
- **Implications**: Implement `natural_compare` as a private helper within the `FileBrowser` module. No shard changes to `shard.yml`.

### Crystal String Iteration and Multibyte Safety

- **Context**: Ensure the segment-splitting algorithm handles UTF-8 filenames (Japanese, full-width chars) without byte-level errors.
- **Sources Consulted**: Crystal stdlib docs (`String#each_char`, `Char#ascii_number?`).
- **Findings**:
  - `String#each_char` yields `Char` values (Unicode codepoints), not raw bytes.
  - `Char#ascii_number?` (or range check `'0' <= c <= '9'`) returns `false` for any non-ASCII codepoint, including multibyte character fragments — there are no false positives.
  - `String#downcase` without arguments applies only to ASCII letters; multibyte characters are passed through unchanged.
- **Implications**: Pre-downcasing the full filename string before passing to `natural_compare` (consistent with existing code) is safe and correct.

### Integer Parsing Strategy for Digit Segments

- **Context**: Choose how to convert a run of digit characters to an integer for comparison.
- **Findings**:
  - Crystal's `String#to_u64?` handles up to 18 digits (max `18_446_744_073_709_551_615`). Filenames in practice never exceed this.
  - `String#to_u64?` returns `nil` on overflow or empty string; both cases can be handled with a fallback to `0u64`.
  - Leading zeros: `"01".to_u64?` returns `1u64`, matching standard natural sort behavior where `file01.png` and `file1.png` compare equal numerically.
- **Implications**: Use `String#to_u64` for digit segment comparison. No `BigInt` needed. Leading zeros are normalized to their integer value.

### Integration Point Confirmation

- **Context**: Verify that all user-facing endpoints share the same sort path.
- **Sources Consulted**: `src/app.cr` — all route handlers.
- **Findings**:
  - All four listing endpoints (`/browse/`, `/browse/*path`, `/api/files/`, `/api/files/*path`) delegate to `FileBrowser.list_entries` with the same `sort_key` / `sort_dir` parameters.
  - The SSR viewer route (`/view/*path`) calls `list_entries` with default params (Name/Asc) for prev/next navigation; natural sort will also apply there.
  - No duplicate sort logic exists outside `FileBrowser`.
- **Implications**: A single change in `scan_entries` propagates to all endpoints. Requirement 5 is satisfied structurally.

---

## Architecture Pattern Evaluation

| Option | Description | Strengths | Risks / Limitations | Notes |
|--------|-------------|-----------|---------------------|-------|
| Private helper in `FileBrowser` | Add `natural_compare` as a private module method | Zero new boundaries; follows existing module pattern; testable via unit tests on the method | None significant | **Selected** |
| Separate `NaturalSort` module | Extract to `src/services/natural_sort.cr` | Reusable outside `FileBrowser` | Over-engineering for a single call site; adds a file | Rejected — YAGNI |
| Inline lambda | Embed segment logic directly in comparator lambda | No new method needed | Unreadable and untestable in isolation | Rejected |

---

## Design Decisions

### Decision: Pre-downcase strings before passing to `natural_compare`

- **Context**: Text segments need case-insensitive comparison, consistent with current `a.name.downcase <=> b.name.downcase`.
- **Alternatives Considered**:
  1. Apply `.downcase` inside `natural_compare` on each text segment — more precise but adds per-segment allocation.
  2. Pre-downcase the full filename string once before the call — consistent with existing code pattern, no behavioral difference.
- **Selected Approach**: Pre-downcase the full string once: `natural_compare(a.name.downcase, b.name.downcase)`.
- **Rationale**: Identical to the existing one-liner pattern; `.downcase` on a digit or multibyte character is a no-op, so the pre-downcase approach produces the same result as per-segment downcase.
- **Trade-offs**: Negligible; `.downcase` allocates a new string once per comparison, same as before.
- **Follow-up**: Verify behavior on filenames that mix ASCII uppercase with digits (e.g., `File10.jpg` vs `file2.jpg`).

### Decision: Do not add `natural_compare` to the public API

- **Context**: `natural_compare` is an implementation detail of `scan_entries`. No other module needs it.
- **Selected Approach**: Declare as `private def self.natural_compare`.
- **Rationale**: Minimizes surface area; aligns with Crystal module visibility idiom.
- **Trade-offs**: Cannot be called directly from spec files; must be tested via `list_entries` or a dedicated spec for the module's internal behavior using the Crystal `private` accessor workaround if needed.
- **Follow-up**: Determine spec strategy — either test via `list_entries` (preferred) or expose with `protected` scope for direct unit tests.

---

## Risks & Mitigations

- **Existing sort tests break** — Pure-alphabetical filenames (`alpha.jpg`, `beta.jpg`, `gamma.jpg`) contain no digits, so natural sort is equivalent to lexicographic sort for them. All existing tests in `file_browser_sort_spec.cr` should pass without modification.
- **Overflow on enormous digit strings** — Mitigated by using `String#to_u64?` with fallback to `0u64`; segments with >20 digits would fall back but such filenames are pathological.
- **Performance regression** — Segment splitting is O(n) per filename where n is character count. Filename lengths are short (typically <255 chars). No measurable impact.

---

## References

- Crystal `String` stdlib docs: `each_char`, `to_u64?`, `downcase` — standard library behavior for UTF-8 iteration and numeric parsing.
- Project CLAUDE.md: shard dependency policy (`kemal` only), `services/` module conventions.
