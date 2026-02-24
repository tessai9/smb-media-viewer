#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# return error if config.yml does not exist
if [ ! -f "$SCRIPT_DIR/config.yml" ]; then
  echo "Error: config.yml not found" >&2
  exit 1
fi

# parse values from config.yml
MEDIA_ROOT=$(grep "^media_root:" "$SCRIPT_DIR/config.yml" | awk '{print $2}')
PORT=$(grep "^port:" "$SCRIPT_DIR/config.yml" | awk '{print $2}')

# resolve relative media_root path based on script location
if [[ "$MEDIA_ROOT" != /* ]]; then
  MEDIA_ROOT="$SCRIPT_DIR/$MEDIA_ROOT"
fi

# run `docker build`
docker build --no-cache -t tesao/media-viewer "$SCRIPT_DIR"

# run docker container with mounting config.yml and directory path mounted to samba via volume
docker rm -f media-viewer 2>/dev/null || true
docker run -d \
  --name media-viewer \
  -v "$SCRIPT_DIR/config.yml:/app/config.yml:ro" \
  -v "$MEDIA_ROOT:/app/mnt:ro" \
  -p "$PORT:$PORT" \
  tesao/media-viewer
