.PHONY: build up down restart logs shell

# Build the dev image
build:
	docker compose build

# Start (rebuild if needed, then run)
up:
	docker compose up --build

# Start in background
up-d:
	docker compose up --build -d

# Stop
down:
	docker compose down

# Restart app (triggers recompile)
restart:
	docker compose restart app

# Tail logs
logs:
	docker compose logs -f app

# Open shell in running container
shell:
	docker compose exec app bash
