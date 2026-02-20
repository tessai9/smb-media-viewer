# Technology Stack

## Architecture

Server-side rendered web app. Initial page load is full HTML; subsequent batches are fetched via JSON API for infinite scroll. No client-side routing.

## Core Technologies

- **Language**: Crystal (compiled binary for low memory overhead)
- **Framework**: Kemal (lightweight HTTP framework for Crystal)
- **Templates**: ECR (Crystal standard library — no extra shards)
- **Frontend**: Vanilla HTML + CSS + JavaScript (no frameworks)

## Key Libraries

- `kemal` — the only Crystal shard dependency
- `libvips` (`vipsthumbnail`) — memory-efficient image resizing
- `ffmpeg` — video frame extraction for thumbnails
- `poppler-utils` (`pdftoppm`) — PDF first-page rendering

## Development Standards

### Crystal Conventions
- Use `include YAML::Serializable` for config (never `YAML.mapping` — deprecated)
- `nil`-safe thumbnail returns: generate functions return `String?`, callers handle fallback
- Path traversal prevention is mandatory on all file-serving routes

### Frontend Constraints
- Total CSS target: 2–3 KB; JS target: 3–4 KB
- Use `IntersectionObserver` for lazy image loading and infinite scroll
- Fallback to eager loading when `IntersectionObserver` is unavailable
- Release image memory when elements scroll out of viewport (`src = ""`)

### Video Streaming
- `/raw/*` must support HTTP `Range` requests (206 Partial Content) for seek support

## Development Environment

### Required Tools
- Docker + Docker Compose (Mac development)
- Crystal 1.15.1 (inside container)
- System packages: `libvips-tools`, `ffmpeg`, `poppler-utils`

### Common Commands
```bash
make up       # Build image and start dev server (crystal run)
make restart  # Recompile after source changes
make logs     # Tail container logs
make shell    # Open shell in container
```

## Key Technical Decisions

- **CIFS mount, not SMB library**: NAS share is pre-mounted at `media_root`; no SMB client library needed, kernel cache reduces latency
- **Disk-cached thumbnails**: Cache key = `SHA256(abs_path + ":" + mtime_unix)` — auto-invalidates on file update
- **SSR first batch**: First `items_per_page` entries rendered server-side; JS fetches subsequent pages from `/api/files/*`

---
_Document standards and patterns, not every dependency_
