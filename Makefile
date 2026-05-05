GODOT ?= godot
PROJECT_DIR := $(CURDIR)

.PHONY: run editor import clean help

run:
	$(GODOT) --path $(PROJECT_DIR) res://scenes/main.tscn

editor:
	$(GODOT) -e --path $(PROJECT_DIR)

import:
	$(GODOT) --headless --import --path $(PROJECT_DIR)

clean:
	rm -rf $(PROJECT_DIR)/.godot

help:
	@echo "make run     - launch game"
	@echo "make editor  - open Godot editor"
	@echo "make import  - reimport assets headless"
	@echo "make clean   - drop .godot cache"
