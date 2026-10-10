.PHONY: all test build run cli watch clean install-swiftbar

PYTHON ?= python3
SWIFTC ?= swiftc
APP_NAME = T3AntigravityContextBar

all: test build

test:
	$(PYTHON) -m unittest discover tests

build:
	@mkdir -p bin $(APP_NAME).app/Contents/MacOS $(APP_NAME).app/Contents/Resources
	$(SWIFTC) -O -framework AppKit -framework Foundation macos_app/Sources/T3ContextBar/*.swift -o bin/$(APP_NAME)
	@cp bin/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/$(APP_NAME)
	@cp macos_app/Resources/Info.plist $(APP_NAME).app/Contents/Info.plist
	@echo "Build successful: bin/$(APP_NAME) & $(APP_NAME).app"

run: build
	open $(APP_NAME).app

cli:
	$(PYTHON) -m t3_monitor

watch:
	$(PYTHON) -m t3_monitor --watch 5

install-swiftbar:
	@mkdir -p "$$HOME/Library/Application Support/SwiftBar/plugins"
	@ln -sf "$(CURDIR)/plugins/swiftbar/t3_tokens.10s.py" "$$HOME/Library/Application Support/SwiftBar/plugins/t3_tokens.10s.py"
	@echo "Symlinked to ~/Library/Application Support/SwiftBar/plugins/t3_tokens.10s.py"

clean:
	rm -rf bin/ *.app *.pyc */*.pyc */*/*.pyc __pycache__ */__pycache__ tests/__pycache__
