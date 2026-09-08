APP     = Sweep
VERSION = 1.0.0
BUNDLE  = dist/$(APP).app
ICON    = Support/Branding/AppIcon.icns
ARCHIVE = dist/$(APP)-$(VERSION).zip

.PHONY: build app run install release clean

build:
	swift build -c release

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	cp ".build/release/$(APP)" "$(BUNDLE)/Contents/MacOS/$(APP)"
	cp "Support/Info.plist" "$(BUNDLE)/Contents/Info.plist"
	cp -R Support/Resources/*.lproj "$(BUNDLE)/Contents/Resources/"
	@if [ -f "$(ICON)" ]; then \
		cp "$(ICON)" "$(BUNDLE)/Contents/Resources/AppIcon.icns"; \
		echo "→ icon: $(ICON)"; \
	else \
		echo "note: $(ICON) not found, building without a custom icon"; \
	fi
	codesign --force --sign - "$(BUNDLE)"
	@echo "→ $(BUNDLE)"

run: app
	open "$(BUNDLE)"

install: app
	@if [ -w /Applications ]; then \
		rm -rf "/Applications/$(APP).app"; \
		ditto "$(BUNDLE)" "/Applications/$(APP).app"; \
		echo "→ /Applications/$(APP).app"; \
	else \
		echo "error: /Applications is not writable by $(USER). Re-run: sudo make install" >&2; \
		exit 1; \
	fi

release: app
	rm -f "$(ARCHIVE)" "$(ARCHIVE).sha256"
	ditto -c -k --keepParent "$(BUNDLE)" "$(ARCHIVE)"
	cd dist && shasum -a 256 "$(notdir $(ARCHIVE))" > "$(notdir $(ARCHIVE)).sha256"
	@echo "→ $(ARCHIVE)"
	@cat "$(ARCHIVE).sha256"

clean:
	swift package clean
	rm -rf dist
