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

.PHONY: all clean upload run refresh-ip deploy-wifi

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
