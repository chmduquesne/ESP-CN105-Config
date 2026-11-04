# Auto-detects which ESP32 is plugged in (by MAC address) and resolves it
# to the matching <room>/main.yaml via a <mac> -> <room>/ directory symlink.
#
# Usage:
#   make register ROOM=bedroom   # link the currently plugged-in board to bedroom/
#   make whoami                  # show detected port/MAC/config for the plugged-in board
#   make compile                 # esphome compile <resolved config>
#   make upload                  # esphome upload <resolved config>
#   make ota ROOM=bedroom        # esphome run <room>/main.yaml over the network (no USB needed)
#   make logs                    # esphome logs <resolved config>
#   make clean                   # esphome clean <resolved config>
#
# Override the port if auto-detection picks the wrong device:
#   make upload PORT=/dev/ttyUSB0

PORT ?= $(shell ls /dev/ttyUSB* 2>/dev/null | head -n1)
MAC  := $(shell test -n "$(PORT)" && esptool.py --port $(PORT) read_mac 2>/dev/null | grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' | head -n1)
CONFIG := $(MAC)/main.yaml

.PHONY: whoami register compile upload ota logs clean check-port check

check-port:
	@test -n "$(PORT)" || { echo "No /dev/ttyUSB* device found. Plug in a board, or pass PORT=/dev/ttyXXX"; exit 1; }
	@test -n "$(MAC)"  || { echo "Could not read a MAC address from $(PORT). Is a board connected there?"; exit 1; }

check: check-port
	@test -f $(CONFIG) || { echo "No config registered for MAC $(MAC). Run: make register ROOM=<name>"; exit 1; }

whoami: check-port
	@echo "Port:   $(PORT)"
	@echo "MAC:    $(MAC)"
	@echo "Config: $(CONFIG)"
	@test -f $(CONFIG) && echo "  -> $$(readlink $(MAC))" || echo "  -> NOT REGISTERED (run: make register ROOM=<name>)"

register: check-port
	@test -n "$(ROOM)" || { echo "Usage: make register ROOM=<name>  (expects <name>/main.yaml to exist)"; exit 1; }
	@test -f $(ROOM)/main.yaml || { echo "$(ROOM)/main.yaml not found"; exit 1; }
	ln -sf $(ROOM) $(MAC)
	@echo "Linked $(MAC) -> $(ROOM)/"

compile: check
	esphome compile $(CONFIG)

upload: check
	esphome compile $(CONFIG)
	esphome upload $(CONFIG) --device $(PORT)

# Over-the-air flash: no USB/MAC detection. Device is reached at
# <device_name>.local; override with HOST=<ip> if mDNS doesn't resolve.
ota:
	@test -n "$(ROOM)" || { echo "Usage: make ota ROOM=<name> [HOST=<ip-or-hostname>]"; exit 1; }
	@test -f $(ROOM)/main.yaml || { echo "$(ROOM)/main.yaml not found"; exit 1; }
	esphome run $(ROOM)/main.yaml --no-logs --device $(or $(HOST),$(ROOM)-ac.local)

logs: check
	esphome logs $(CONFIG) --device $(PORT)

clean: check
	esphome clean $(CONFIG)
