WORKSPACE:=iOS.xcworkspace
SCHEME:=KSCrashLib
SDK:=iphonesimulator
BUILD_ARGS=-workspace $(WORKSPACE) -scheme $(SCHEME) -sdk $(SDK)

all: build

.PHONY: build lint test

build: ## Build the selected target. Default is iOS.
	xcodebuild $(BUILD_ARGS) build

lint: ## Lint the podspec
	pod lib lint

test: ## Test the selected target
	xcodebuild $(BUILD_ARGS) test

help: ## Show help text
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
