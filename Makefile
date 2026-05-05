GODOT ?= godot
PROJECT_DIR := $(CURDIR)

# Dedicated server defaults — override on the command line:
#   make server PORT=9999 MIN_PLAYERS=3
PORT        ?= 7777
MIN_PLAYERS ?= 2

.PHONY: run editor import smoke check server peer host join clean help

run: check
	$(GODOT) --path $(PROJECT_DIR)

editor:
	$(GODOT) -e --path $(PROJECT_DIR)

import:
	$(GODOT) --headless --import --path $(PROJECT_DIR)

smoke:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/smoke_test/smoke_test.tscn

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

clean:
	rm -rf $(PROJECT_DIR)/.godot

help:
	@echo "make run              - check scripts then launch game (lobby)"
	@echo "make server           - headless dedicated server (default PORT=7777 MIN_PLAYERS=2)"
	@echo "make check            - parse-check all GDScript (headless, 90 frames)"
	@echo "make editor           - open Godot editor"
	@echo "make import           - reimport assets headless"
	@echo "make smoke            - run headless smoke test"
	@echo "make peer             - two windows for local multiplayer testing"
	@echo "make clean            - drop .godot cache"
