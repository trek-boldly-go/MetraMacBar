APP      = MetraTracker.app
BINARY   = .build/release/MetraTracker
ARCH    ?= $(shell uname -m)

.PHONY: build package run clean

build:
	swift build -c release --arch $(ARCH)

package: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	mkdir -p $(APP)/Contents/Resources
	cp $(BINARY) $(APP)/Contents/MacOS/
	cp Resources/Info.plist $(APP)/Contents/
	codesign --sign - --force --deep $(APP)
	@echo "Built $(APP)"

run: package
	open $(APP)

clean:
	rm -rf .build $(APP)
