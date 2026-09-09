APP     = Sweep
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist 2>/dev/null)
BUNDLE  = dist/$(APP).app
ICON    = Support/Branding/AppIcon.icns
STAGE   = dist/release
ARCHIVE = dist/$(APP)-$(VERSION).zip
DMG     = dist/$(APP)-$(VERSION).dmg

.PHONY: build app run install release dmg clean

build:
	@if swift build -c release --arch arm64 --arch x86_64; then \
		echo "→ universal binary (arm64 + x86_64)"; \
	else \
		echo "note: universal build unavailable, falling back to the native architecture"; \
		rm -rf ".build/apple/Products/Release/$(APP)"; \
		swift build -c release; \
	fi

app: build
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	@if [ -f ".build/apple/Products/Release/$(APP)" ]; then \
		cp ".build/apple/Products/Release/$(APP)" "$(BUNDLE)/Contents/MacOS/$(APP)"; \
	else \
		cp ".build/release/$(APP)" "$(BUNDLE)/Contents/MacOS/$(APP)"; \
	fi
	cp "Support/Info.plist" "$(BUNDLE)/Contents/Info.plist"
	cp -R Support/Resources/*.lproj "$(BUNDLE)/Contents/Resources/"
	@if [ -f "$(ICON)" ]; then \
		cp "$(ICON)" "$(BUNDLE)/Contents/Resources/AppIcon.icns"; \
		echo "→ icon: $(ICON)"; \
	else \
		echo "note: $(ICON) not found, building without a custom icon"; \
	fi
	codesign --force --sign - "$(BUNDLE)"
	@lipo -info "$(BUNDLE)/Contents/MacOS/$(APP)"
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
	@test -n "$(VERSION)" || { echo "error: could not read CFBundleShortVersionString from Support/Info.plist" >&2; exit 1; }
	./dist/Sweep.app/Contents/MacOS/Sweep --selftest
	plutil -lint "$(BUNDLE)/Contents/Info.plist"
	codesign --verify --deep --strict "$(BUNDLE)"
	rm -rf "$(STAGE)" "$(ARCHIVE)" "$(ARCHIVE).sha256"
	mkdir -p "$(STAGE)"
	ditto "$(BUNDLE)" "$(STAGE)/$(APP).app"
	cp LICENSE README.md "$(STAGE)/"
	ditto -c -k --norsrc "$(STAGE)" "$(ARCHIVE)"
	cd dist && shasum -a 256 "$(notdir $(ARCHIVE))" > "$(notdir $(ARCHIVE)).sha256"
	cd dist && shasum -a 256 -c "$(notdir $(ARCHIVE)).sha256"
	@echo "→ $(ARCHIVE)"
	@cat "$(ARCHIVE).sha256"

dmg: release
	rm -rf dist/dmg "$(DMG)" "$(DMG).sha256"
	mkdir -p dist/dmg
	ditto "$(BUNDLE)" "dist/dmg/$(APP).app"
	ln -s /Applications "dist/dmg/Applications"
	hdiutil create -volname "$(APP) $(VERSION)" -srcfolder dist/dmg -ov -format UDZO "$(DMG)"
	rm -rf dist/dmg
	cd dist && shasum -a 256 "$(notdir $(DMG))" > "$(notdir $(DMG)).sha256"
	cd dist && shasum -a 256 -c "$(notdir $(DMG)).sha256"
	@echo "→ $(DMG)"
	@cat "$(DMG).sha256"

clean:
	swift package clean
	rm -rf dist
