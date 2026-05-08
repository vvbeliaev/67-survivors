GODOT ?= godot
PROJECT_DIR := $(CURDIR)

# Dedicated server defaults — override on the command line:
#   make server PORT=9999 MIN_PLAYERS=3
PORT        ?= 7777
MIN_PLAYERS ?= 2

# Remote deploy settings:
#   make deploy IP=1.2.3.4
#   make deploy IP=1.2.3.4 SSH_PORT=2222 USER=ubuntu KEY=~/.ssh/other_key
IP       ?=
KEY      ?= ~/.ssh/id_ed25519_selectel
SSH_PORT ?= 22
USER     ?= root

.PHONY: run editor import smoke rarity-test bcleave-test check server deploy logs stop peer host join clean help

run: check
	$(GODOT) --path $(PROJECT_DIR)

editor:
	$(GODOT) -e --path $(PROJECT_DIR)

import:
	$(GODOT) --headless --import --path $(PROJECT_DIR)

smoke:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/smoke_test/smoke_test.tscn

rarity-test:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/rarity_offer/rarity_offer.tscn

bcleave-test:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/berserker_cleave/berserker_cleave.tscn

# Headless dedicated server. Clients connect from the lobby (Join + server IP).
# The round starts automatically once MIN_PLAYERS players are in the roster.
server:
	$(GODOT) --headless --path $(PROJECT_DIR) res://src/server/server.tscn -- --port $(PORT) --min-players $(MIN_PLAYERS)

# Two-window manual multiplayer test: run twice, host with one, join with the other.
peer:
	$(GODOT) --path $(PROJECT_DIR) &
	$(GODOT) --path $(PROJECT_DIR)

# Parse-check all GDScript without opening a window.
# Runs the project headless for 90 frames — enough to load main scene and
# trigger _ready() on every autoload. Fails (exit 1) on any SCRIPT ERROR or
# Parse Error, so CI and `make run` catch broken scripts before launch.
check:
	@echo "Checking GDScript..."
	@$(GODOT) --headless --path $(PROJECT_DIR) --quit-after 90 2>&1 | tee /tmp/godot_check.log; \
	if grep -qE "SCRIPT ERROR|Parse Error" /tmp/godot_check.log; then \
		echo ""; \
		echo "GDScript errors detected:"; \
		grep -E "SCRIPT ERROR|Parse Error" /tmp/godot_check.log; \
		exit 1; \
	else \
		echo "OK"; \
	fi

# ── Remote server management ────────────────────────────────────────────────

# Install Godot + pull repo + open port + start server — all in one shot.
deploy:
	@[ -n "$(IP)" ] || (echo "Usage: make deploy IP=<ip> [SSH_PORT=22] [USER=root] [KEY=~/.ssh/id_ed25519_selectel] [PORT=7777]"; exit 1)
	@bash $(PROJECT_DIR)/scripts/deploy.sh "$(IP)" "$(KEY)" "$(PORT)" "$(SSH_PORT)" "$(USER)"

# Tail server logs in real time.
logs:
	@[ -n "$(IP)" ] || (echo "Usage: make logs IP=<ip> [SSH_PORT=22] [USER=root]"; exit 1)
	ssh -i "$(KEY)" -p "$(SSH_PORT)" -o StrictHostKeyChecking=no $(USER)@$(IP) tail -f /var/log/67survivors.log

# Kill the running server process.
stop:
	@[ -n "$(IP)" ] || (echo "Usage: make stop IP=<ip> [SSH_PORT=22] [USER=root]"; exit 1)
	ssh -i "$(KEY)" -p "$(SSH_PORT)" -o StrictHostKeyChecking=no $(USER)@$(IP) \
	    'kill $$(cat /var/run/67survivors.pid 2>/dev/null) 2>/dev/null && echo stopped || echo not running'

clean:
	rm -rf $(PROJECT_DIR)/.godot

help:
	@echo "make run                       - check scripts then launch game (lobby)"
	@echo "make deploy IP=x [SSH_PORT=22] [USER=root]  - install + start server"
	@echo "make logs   IP=x [SSH_PORT=22] [USER=root]  - tail server logs"
	@echo "make stop   IP=x [SSH_PORT=22] [USER=root]  - kill server process"
	@echo "make server [PORT=7777]        - headless server locally"
	@echo "make check                     - parse-check all GDScript"
	@echo "make editor                    - open Godot editor"
	@echo "make import                    - reimport assets headless"
	@echo "make smoke                     - run headless smoke test"
	@echo "make peer                      - two windows for local multiplayer"
	@echo "make clean                     - drop .godot cache"
