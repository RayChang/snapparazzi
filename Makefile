SWIFTC ?= xcrun swiftc
SWIFT_FLAGS := -emit-executable -O -whole-module-optimization -warnings-as-errors
BUILD_DIR ?= .build
SOURCE_DIR := Sources/Snapparazzi
# Every production Swift file, nested folders included, in a stable order.
SOURCES := $(shell find $(SOURCE_DIR) -type f -name '*.swift' | LC_ALL=C sort)
BINARY := $(BUILD_DIR)/snapparazzi
# Records the compiler, flags and source list; rewritten only when they change,
# so adding/removing a file or changing flags rebuilds, and nothing else does.
BUILD_INPUTS := $(BUILD_DIR)/build-inputs.txt
PREFIX ?= $(HOME)/.local

.PHONY: all build test install clean FORCE

all: build

build: $(BINARY)

$(BUILD_INPUTS): FORCE
	@mkdir -p $(BUILD_DIR)
	@printf '%s\n' '$(SWIFTC) $(SWIFT_FLAGS)' $(SOURCES) > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else mv $@.tmp $@; fi

$(BINARY): $(SOURCES) $(BUILD_INPUTS) Makefile
	$(SWIFTC) $(SWIFT_FLAGS) $(SOURCES) -o $(BINARY)

test: build
	tests/run-tests.sh
	tests/install-tests.sh

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(BINARY) $(DESTDIR)$(PREFIX)/bin/snapparazzi

clean:
	rm -rf $(BUILD_DIR)
