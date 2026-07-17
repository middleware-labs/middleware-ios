PROJECT_NAME = "middleware-ios"

XCODEBUILD_OPTIONS_IOS = \
	-configuration Debug \
	-destination platform='iOS Simulator,name=iPhone 17,OS=latest' \
	-scheme $(PROJECT_NAME) \
	-workspace .

XCODEBUILD_OPTIONS_TVOS = \
	-configuration Debug \
	-destination platform='tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest' \
	-scheme $(PROJECT_NAME) \
	-workspace .

XCODEBUILD_OPTIONS_WATCHOS = \
	-configuration Debug \
	-destination platform='watchOS Simulator,name=Apple Watch Series 8 (45mm),OS=latest' \
	-scheme $(PROJECT_NAME) \
	-workspace .

# --- CoffeeCart sample (Examples/MiddlewareApp) ---
SAMPLE_PROJECT = Examples/MiddlewareApp/MiddlewareApp.xcodeproj
SAMPLE_SCHEME = MiddlewareApp
SAMPLE_BUNDLE = io.middleware.MiddlewareApp
SIM_NAME ?= iPhone 17
DERIVED_DATA ?= Examples/MiddlewareApp/build/DerivedData
SAMPLE_APP = $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/MiddlewareApp.app
SAMPLE_DSYM = $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/MiddlewareApp.app.dSYM

XCODEBUILD_SAMPLE = \
	xcodebuild \
	-project $(SAMPLE_PROJECT) \
	-scheme $(SAMPLE_SCHEME) \
	-configuration Debug \
	-destination 'platform=iOS Simulator,name=$(SIM_NAME)' \
	-derivedDataPath $(DERIVED_DATA) \
	DEBUG_INFORMATION_FORMAT=dwarf-with-dsym

.PHONY: upload-dsym
upload-dsym:
	@test -n "$(MW_API_KEY)" || (echo "Set MW_API_KEY"; exit 1)
	@test -n "$(DSYM_PATH)" || (echo "Set DSYM_PATH=/path/to/App.app.dSYM"; exit 1)
	./Tools/dsym-upload/upload-dsym.sh \
		--api-key "$(MW_API_KEY)" \
		--version "$(or $(MW_APP_VERSION),1.0.0)" \
		--path "$(DSYM_PATH)"

.PHONY: build-sample-ios
build-sample-ios:
	set -o pipefail && $(XCODEBUILD_SAMPLE) build | xcbeautify

.PHONY: run-sample-ios
run-sample-ios: build-sample-ios
	xcrun simctl boot "$(SIM_NAME)" 2>/dev/null || true
	open -a Simulator
	xcrun simctl install booted "$(SAMPLE_APP)"
	xcrun simctl launch booted $(SAMPLE_BUNDLE)

.PHONY: upload-dsym-sample
upload-dsym-sample:
	@test -n "$(MW_API_KEY)" || (echo "Set MW_API_KEY"; exit 1)
	@test -d "$(or $(DSYM_PATH),$(SAMPLE_DSYM))" || (echo "dSYM not found. Run make build-sample-ios first."; exit 1)
	./Tools/dsym-upload/upload-dsym.sh \
		--api-key "$(MW_API_KEY)" \
		--version "$(or $(MW_APP_VERSION),1.0)" \
		--path "$(or $(DSYM_PATH),$(SAMPLE_DSYM))"

.PHONY: build-run-upload-dsym
build-run-upload-dsym: run-sample-ios upload-dsym-sample

.PHONY: setup-brew
setup-brew:
	brew update && brew install xcbeautify

.PHONY: build-ios
build-ios:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) build | xcbeautify

.PHONY: build-tvos
build-tvos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_TVOS) build | xcbeautify

.PHONY: build-watchos
build-watchos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) build | xcbeautify

.PHONY: build-for-testing-ios
build-for-testing-ios:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) build-for-testing | xcbeautify

.PHONY: build-for-testing-tvos
build-for-testing-tvos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_TVOS) build-for-testing | xcbeautify

.PHONY: build-for-testing-watchos
build-for-testing-watchos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_WATCHOS) build-for-testing | xcbeautify

.PHONY: test-ios
test-ios:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) test | xcbeautify

.PHONY: test-tvos
test-tvos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_TVOS) test | xcbeautify

.PHONY: test-watchos
test-watchos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_WATCHOS) test | xcbeautify

.PHONY: test-without-building-ios
test-without-building-ios:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_IOS) test-without-building | xcbeautify

.PHONY: test-without-building-tvos
test-without-building-tvos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_TVOS) test-without-building | xcbeautify

.PHONY: test-without-building-watchos
test-without-building-watchos:
	set -o pipefail && xcodebuild $(XCODEBUILD_OPTIONS_WATCHOS) test-without-building | xcbeautify
