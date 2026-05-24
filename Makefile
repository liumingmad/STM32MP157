CC      := zig cc
TARGET  := arm-linux-gnueabihf.2.30
CFLAGS  := -target $(TARGET) -Wall -O2

SRC_DIR   := src
BUILD_DIR := build
REMOTE_HOST := mp157
REMOTE_DIR  := ~/_work/test
REMOTE      := $(REMOTE_HOST):$(REMOTE_DIR)

SRCS := $(wildcard $(SRC_DIR)/*.c)
BINS := $(patsubst $(SRC_DIR)/%.c,$(BUILD_DIR)/%,$(SRCS))

.PHONY: all clean upload run refresh-ip deploy-wifi vnc-demo vnc-stop vnc-open

all: $(BINS)

upload: $(BINS)
	scp $(BINS) $(REMOTE)

# Usage: make run PROG=hello  (defaults to first binary)
PROG ?= $(notdir $(firstword $(BINS)))
run: upload
	ssh $(REMOTE_HOST) "$(REMOTE_DIR)/$(PROG)"

$(BUILD_DIR)/%: $(SRC_DIR)/%.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -o $@ $<

$(BUILD_DIR):
	mkdir -p $@

clean:
	rm -rf $(BUILD_DIR)

# If ssh to the board fails, query the new IP over serial and update ~/.ssh/config.
refresh-ip:
	python3 scripts/refresh-mp157-ip.py

# Install the wifi-autoconnect unit + its EnvironmentFile on the board.
# The .env file holds the WiFi password — it is gitignored, so a fresh
# clone must copy systemd/wifi-autoconnect.env.example to .env first.
deploy-wifi:
	@test -f systemd/wifi-autoconnect.env || { \
	  echo "missing systemd/wifi-autoconnect.env — copy .env.example and fill in real creds"; \
	  exit 1; }
	scp systemd/wifi-autoconnect.env     $(REMOTE_HOST):/tmp/wifi-autoconnect.env
	scp systemd/wifi-autoconnect.service $(REMOTE_HOST):/tmp/wifi-autoconnect.service
	ssh $(REMOTE_HOST) '\
	  install -m 0600 /tmp/wifi-autoconnect.env     /etc/default/wifi-autoconnect && \
	  install -m 0644 /tmp/wifi-autoconnect.service /etc/systemd/system/wifi-autoconnect.service && \
	  rm /tmp/wifi-autoconnect.env /tmp/wifi-autoconnect.service && \
	  systemctl daemon-reload && \
	  systemctl enable --now wifi-autoconnect.service && \
	  systemctl restart wifi-autoconnect.service && \
	  systemctl is-active wifi-autoconnect.service'

# --- Qt-VNC demo: run a QML on the board, view it from this Mac ---
# Usage:
#   make vnc-demo                       # uploads qt/demo.qml and opens VNC viewer
#   make vnc-demo QML=path/to/x.qml     # run your own QML file
#   make vnc-demo VNC_SIZE=1024x600     # change resolution
#   make vnc-stop                       # kill the Qt-VNC process on the board
#   make vnc-open                       # just open the Mac VNC client (board must already be running)
#
# The Qt VNC platform plugin only supports software (raster) rendering — fine for
# normal UI, but Qt3D / Shader Effects / Qt Quick 3D won't render.
VNC_SIZE  ?= 800x480
QML       ?= qt/demo.qml
REMOTE_QML := /tmp/$(notdir $(QML))
# Resolve the board's real hostname/IP via ssh config (refresh-ip keeps it in sync).
VNC_HOST = $(shell ssh -G $(REMOTE_HOST) 2>/dev/null | awk '/^hostname / {print $$2}')

vnc-demo:
	@test -f $(QML) || { echo "missing $(QML)"; exit 1; }
	scp $(QML) $(REMOTE_HOST):$(REMOTE_QML)
	ssh $(REMOTE_HOST) ' \
	  pkill -x qmlscene 2>/dev/null; true; sleep 1; \
	  setsid qmlscene -platform vnc:size=$(VNC_SIZE) $(REMOTE_QML) \
	    </dev/null >/tmp/vnc.log 2>&1 & \
	  sleep 2; \
	  grep -q "QVncServer created" /tmp/vnc.log \
	    && echo "VNC server up on port 5900" \
	    || { echo "--- /tmp/vnc.log ---"; cat /tmp/vnc.log; exit 1; }'
	@echo "Opening vnc://$(VNC_HOST):5900 ..."
	@open vnc://$(VNC_HOST):5900

vnc-stop:
	ssh $(REMOTE_HOST) 'pkill -x qmlscene 2>/dev/null; true; echo stopped'

vnc-open:
	@open vnc://$(VNC_HOST):5900
