# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM crystallang/crystal:1.15.1 AS builder

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libvips-tools \
    && rm -rf /var/lib/apt/lists/*

COPY shard.yml shard.lock* ./
RUN shards install --without-development

COPY src/ /app/src/
RUN crystal build src/app.cr --release -o media-viewer

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    libvips-tools \
    ffmpeg \
    poppler-utils \
    libgc1 \
    libevent-2.1-7 \
    libpcre2-8-0 \
    libssl3 \
    zlib1g \
    libyaml-0-2 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/media-viewer ./media-viewer

COPY public/ ./public/

# Mount point for the SMB share (bind-mounted at runtime)
RUN mkdir -p mnt

EXPOSE 3000

CMD ["./media-viewer"]
