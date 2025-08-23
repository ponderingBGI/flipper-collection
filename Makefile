# Mouse and keyboard Jiggler - Flipper Zero Application
# Build instructions for Flipper Zero firmware

APP_NAME = mousejiggler
APP_DIR = applications/external/$(APP_NAME)

.PHONY: build install clean help

help:
	@echo "Mouse and keyboard Jiggler - Build Commands"
	@echo "=================================="
	@echo "build   - Build the application (.fap file)"
	@echo "install - Copy files to Flipper firmware directory"
	@echo "clean   - Clean build artifacts"
	@echo "help    - Show this help message"
	@echo ""
	@echo "Prerequisites:"
	@echo "- Flipper Zero firmware source code"
	@echo "- Set FLIPPER_FW_PATH environment variable"

build:
	@if [ -z "$(FLIPPER_FW_PATH)" ]; then \
		echo "Error: FLIPPER_FW_PATH environment variable not set"; \
		echo "Please set it to your Flipper Zero firmware directory"; \
		exit 1; \
	fi
	cd $(FLIPPER_FW_PATH) && ./fbt fap_$(APP_NAME)

install:
	@if [ -z "$(FLIPPER_FW_PATH)" ]; then \
		echo "Error: FLIPPER_FW_PATH environment variable not set"; \
		exit 1; \
	fi
	@echo "Installing source files to firmware directory..."
	mkdir -p $(FLIPPER_FW_PATH)/$(APP_DIR)
	cp mousejiggler.c $(FLIPPER_FW_PATH)/$(APP_DIR)/
	cp application.fam $(FLIPPER_FW_PATH)/$(APP_DIR)/
	cp -r icons $(FLIPPER_FW_PATH)/$(APP_DIR)/ 2>/dev/null || true
	@echo "Files installed successfully!"
	@echo "Now run: make build"

clean:
	@if [ -n "$(FLIPPER_FW_PATH)" ]; then \
		cd $(FLIPPER_FW_PATH) && ./fbt fap_$(APP_NAME) --clean; \
	fi
	@echo "Clean completed!"

# Quick build and install
all: install build
	@echo "Build completed! Check $(FLIPPER_FW_PATH)/dist/ for the .fap file"
