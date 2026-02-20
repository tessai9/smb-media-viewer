# Project Structure

## Organization Philosophy

Layered by responsibility: entry point → services → views → public assets. Services are pure logic (no HTTP); routing lives exclusively in `app.cr`.

## Directory Patterns

### Entry Point
**Location**: `src/app.cr`
**Purpose**: Kemal route definitions and server startup. Thin — delegates all logic to services.
**Example**: Route handler reads config, calls `FileBrowser`, renders ECR template.

### Services
**Location**: `src/services/`
**Purpose**: Business logic, no HTTP concerns. Each file owns one domain.
- `mime.cr` — extension → Content-Type / MediaType enum
- `file_browser.cr` — directory scan, sorting, pagination, path safety
- `thumbnail.cr` — thumbnail generation and disk cache management

### Views (ECR Templates)
**Location**: `src/views/`
**Purpose**: HTML rendering. Templates receive typed local variables from route handlers.
- `layout.ecr` — shared HTML shell (head, nav, scripts)
- `directory.ecr` — thumbnail grid, embedded in layout
- `viewer.ecr` — single-file viewer (image/video/PDF), embedded in layout

### Static Assets
**Location**: `public/`
**Purpose**: Served directly by Kemal. Keep small — CSS ≤3 KB, JS ≤4 KB.

### Configuration
**Location**: `config.yml` (runtime), `src/config.cr` (loader)
**Purpose**: `config.cr` defines the struct with defaults; `config.yml` overrides for deployment.

### Dev Infrastructure
**Location**: `Dockerfile.dev`, `docker-compose.yml`, `Makefile`
**Purpose**: Mac-based Docker development. `test-media/` is the local substitute for the CIFS mount.

## Naming Conventions

- **Crystal files**: `snake_case.cr`
- **ECR templates**: `snake_case.ecr`
- **CSS/JS**: `snake_case` or single-word (`style.css`, `app.js`)
- **Structs/Classes**: `PascalCase` (e.g., `FileEntry`, `AppConfig`)
- **Methods**: `snake_case`

## Code Organization Principles

- Services have no knowledge of HTTP (no `env`, no `context`)
- Route handlers are thin: validate input → call service → render or respond
- Path safety is enforced in `file_browser.cr` before any file I/O
- Thumbnail generation failures are non-fatal: return `nil`, serve fallback image

---
_Document patterns, not file trees. New files following patterns shouldn't require updates_
