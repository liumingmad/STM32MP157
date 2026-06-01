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

.PHONY: all clean upload run refresh-ip deploy-wifi vnc-demo vnc-stop vnc-open deploy-led led-status led-stop driver-image driver-prepare-stable driver-prepare-archive driver-build driver-clean driver-shell

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

# --- LED HTTP daemon: lets the QML UI drive /sys/class/leds/user-led ---
# Usage:
#   make deploy-led    # cross-build led, install binary + daemon + service, start
#   make led-status    # systemctl status + current sysfs state via the daemon
#   make led-stop      # disable + stop the service
deploy-led: $(BUILD_DIR)/led
	scp $(BUILD_DIR)/led            $(REMOTE_HOST):/tmp/led
	scp scripts/led-daemon.py       $(REMOTE_HOST):/tmp/led-daemon.py
	scp systemd/led-daemon.service  $(REMOTE_HOST):/tmp/led-daemon.service
	ssh $(REMOTE_HOST) ' \
	  install -d /usr/local/bin && \
	  install -m 0755 /tmp/led                /usr/local/bin/led && \
	  install -m 0755 /tmp/led-daemon.py      /usr/local/bin/led-daemon.py && \
	  install -m 0644 /tmp/led-daemon.service /etc/systemd/system/led-daemon.service && \
	  rm /tmp/led /tmp/led-daemon.py /tmp/led-daemon.service && \
	  systemctl daemon-reload && \
	  systemctl enable --now led-daemon.service && \
	  systemctl restart led-daemon.service && \
	  systemctl is-active led-daemon.service'

led-status:
	@ssh $(REMOTE_HOST) ' \
	  systemctl status led-daemon.service --no-pager -l | head -20; \
	  echo "--- GET /led ---"; \
	  curl -sS http://127.0.0.1:8081/led | python3 -m json.tool'

led-stop:
	ssh $(REMOTE_HOST) 'systemctl disable --now led-daemon.service; echo stopped'

# --- STM32MP157 out-of-tree driver development via OrbStack/Docker ---
driver-image:
	scripts/driver-dev.sh build-image

driver-prepare-stable:
	scripts/driver-dev.sh prepare-stable

driver-prepare-archive:
	scripts/driver-dev.sh prepare-archive

driver-build:
	scripts/driver-dev.sh build

driver-clean:
	scripts/driver-dev.sh clean

driver-shell:
	scripts/driver-dev.sh shell
