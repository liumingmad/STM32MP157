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

.PHONY: all clean upload run refresh-ip

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
