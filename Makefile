SWIFTC ?= xcrun swiftc
BUILD_DIR ?= .build
SOURCE := Sources/Snapparazzi/main.swift
BINARY := $(BUILD_DIR)/snapparazzi
PREFIX ?= $(HOME)/.local

.PHONY: all build test install clean

all: build

build: $(BINARY)

$(BINARY): $(SOURCE)
	mkdir -p $(BUILD_DIR)
	$(SWIFTC) -emit-executable -O -whole-module-optimization -warnings-as-errors $(SOURCE) -o $(BINARY)

test: build
	tests/run-tests.sh

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(BINARY) $(DESTDIR)$(PREFIX)/bin/snapparazzi

clean:
	rm -rf $(BUILD_DIR)
