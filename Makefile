APP_NAME    = Grid
BUNDLE_ID   = ro.pom.grid
BUILD_DIR   = .build/release
APP_BUNDLE  = build/$(APP_NAME).app
CONTENTS    = $(APP_BUNDLE)/Contents
INSTALL_DIR = /Applications

.PHONY: build install clean run

build:
	swift build -c release
	@mkdir -p $(CONTENTS)/MacOS
	@mkdir -p $(CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(CONTENTS)/MacOS/
	cp Sources/Info.plist $(CONTENTS)/
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/
	cp Resources/Assets.car $(CONTENTS)/Resources/
	cp Resources/menubar_icon.png $(CONTENTS)/Resources/
	cp -R $(BUILD_DIR)/Grid_Grid.bundle $(CONTENTS)/Resources/
	@# Remove raw xcassets from bundle — pre-compiled Assets.car is used instead
	rm -rf $(CONTENTS)/Resources/Grid_Grid.bundle/Assets.xcassets
	@# Ad-hoc code sign for local development
	codesign --force --sign - --deep $(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

install: build
	@echo "Installing to $(INSTALL_DIR)..."
	cp -R $(APP_BUNDLE) $(INSTALL_DIR)/
	@echo "Installed $(APP_NAME).app"

run: build
	open $(APP_BUNDLE)

clean:
	rm -rf build .build
