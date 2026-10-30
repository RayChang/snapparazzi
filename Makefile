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

# Info.plist is embedded in the binary (microphone usage text, stable identifier)
# and is the only place the version is written; BuildMetadata.swift is generated from it.
PLIST := Resources/Info.plist
BUNDLE_ID := dev.snapparazzi.cli
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' $(PLIST) 2>/dev/null)
METADATA := $(BUILD_DIR)/Generated/BuildMetadata.swift
LINK_FLAGS := -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(PLIST)

# Recording tests: production sources without the product entry point, plus test code.
LIBRARY_SOURCES := $(filter-out $(SOURCE_DIR)/main.swift,$(SOURCES)) $(METADATA)
SUPPORT_SOURCES := $(shell find tests/RecordingSupport -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort)
TEST_SOURCES := $(shell find tests/RecordingTests -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort)
TEST_BINARY := $(BUILD_DIR)/recording-tests
INSPECT_SOURCES := $(shell find tests/RecordingInspect -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort)
INSPECT_BINARY := $(BUILD_DIR)/recording-inspect
FIXTURE_SOURCES := $(shell find tests/RecordingFixtureApp -type f -name '*.swift' 2>/dev/null | LC_ALL=C sort)
FIXTURE_BINARY := $(BUILD_DIR)/recording-fixture-app
FIXTURE_APP := $(BUILD_DIR)/RecordingFixture.app

.PHONY: all build test test-recording recording-inspect recording-acceptance install clean FORCE

all: build

build: $(BINARY)

$(BUILD_INPUTS): FORCE
	@mkdir -p $(BUILD_DIR)
	@printf '%s\n' '$(SWIFTC) $(SWIFT_FLAGS) $(LINK_FLAGS) $(BUNDLE_ID)' $(SOURCES) > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else mv $@.tmp $@; fi

$(METADATA): $(PLIST) FORCE
	@plutil -lint -s $(PLIST)
	@printf '%s' '$(VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "$(PLIST): CFBundleShortVersionString must look like 1.2.3 (got '$(VERSION)')" >&2; exit 1; }
	@mkdir -p $(dir $@)
	@printf '// Generated from %s by the Makefile. Do not edit.\nlet snapparazziVersion = "%s"\n' '$(PLIST)' '$(VERSION)' > $@.tmp
	@if cmp -s $@.tmp $@; then rm -f $@.tmp; else mv $@.tmp $@; fi

$(BINARY): $(SOURCES) $(METADATA) $(PLIST) $(BUILD_INPUTS) Makefile
	$(SWIFTC) $(SWIFT_FLAGS) $(SOURCES) $(METADATA) $(LINK_FLAGS) -o $(BINARY)
	codesign --force --sign - --identifier $(BUNDLE_ID) $(BINARY)

$(TEST_BINARY): $(LIBRARY_SOURCES) $(SUPPORT_SOURCES) $(TEST_SOURCES) $(BUILD_INPUTS) Makefile
	$(SWIFTC) $(SWIFT_FLAGS) $(LIBRARY_SOURCES) $(SUPPORT_SOURCES) $(TEST_SOURCES) -o $(TEST_BINARY)

$(INSPECT_BINARY): $(SUPPORT_SOURCES) $(INSPECT_SOURCES) $(BUILD_INPUTS) Makefile
	$(SWIFTC) $(SWIFT_FLAGS) $(SUPPORT_SOURCES) $(INSPECT_SOURCES) -o $(INSPECT_BINARY)

recording-inspect: $(INSPECT_BINARY)

$(FIXTURE_BINARY): $(FIXTURE_SOURCES) $(BUILD_INPUTS) Makefile
	$(SWIFTC) $(SWIFT_FLAGS) $(FIXTURE_SOURCES) -o $(FIXTURE_BINARY)

# The fixture runs as its own .app (launched with open -n), not as a terminal child.
$(FIXTURE_APP): $(FIXTURE_BINARY)
	rm -rf $@
	mkdir -p $@/Contents/MacOS
	cp $(FIXTURE_BINARY) $@/Contents/MacOS/RecordingFixture
	/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.snapparazzi.recording-fixture' \
		-c 'Add :CFBundleExecutable string RecordingFixture' -c 'Add :CFBundlePackageType string APPL' \
		-c 'Add :CFBundleName string RecordingFixture' $@/Contents/Info.plist >/dev/null
	codesign --force --sign - $@

# Opt-in real recordings on this Mac (needs Screen Recording/Microphone permission and a GUI).
recording-acceptance: build $(INSPECT_BINARY) $(FIXTURE_APP)
	tests/recording-acceptance.sh

test-recording: $(TEST_BINARY)
	$(TEST_BINARY)

test: build test-recording
	tests/run-tests.sh
	tests/record-cli-tests.sh
	tests/install-tests.sh

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(BINARY) $(DESTDIR)$(PREFIX)/bin/snapparazzi

clean:
	rm -rf $(BUILD_DIR)
