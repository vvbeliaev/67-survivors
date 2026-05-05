GODOT ?= godot
PROJECT_DIR := $(CURDIR)

.PHONY: run editor import smoke peer host join clean help

run:
	$(GODOT) --path $(PROJECT_DIR)

editor:
	$(GODOT) -e --path $(PROJECT_DIR)

import:
	$(GODOT) --headless --import --path $(PROJECT_DIR)

smoke:
	$(GODOT) --path $(PROJECT_DIR) --headless res://tests/smoke_test/smoke_test.tscn

# Two-window manual multiplayer test: run twice, host with one, join with the other.
peer:
	$(GODOT) --path $(PROJECT_DIR) &
	$(GODOT) --path $(PROJECT_DIR)

clean:
	rm -rf $(PROJECT_DIR)/.godot

help:
	@echo "make run     - launch game (lobby scene)"
	@echo "make editor  - open Godot editor"
	@echo "make import  - reimport assets headless"
	@echo "make smoke   - run headless smoke test (asserts core systems tick)"
	@echo "make peer    - launch two windows for local multiplayer testing"
	@echo "make clean   - drop .godot cache"
