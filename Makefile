.DEFAULT_GOAL := help

SDK_DIR := packages/formbricks_flutter
PLAYGROUND_DIR := apps/playground
TEST_RESULTS_DIR := test-results
PLATFORMS := ios android
PLATFORM_GOAL := $(firstword $(filter $(PLATFORMS),$(MAKECMDGOALS)))
PLATFORM ?=
RUN_PLATFORM := $(or $(PLATFORM),$(PLATFORM_GOAL),ios)
BUILD_PLATFORM := $(or $(PLATFORM),$(PLATFORM_GOAL),android)

ifeq ($(shell command -v fvm >/dev/null 2>&1 && echo yes),yes)
FLUTTER := fvm flutter
DART := fvm dart
else
FLUTTER := flutter
DART := dart
endif

MELOS := $(DART) run melos

.PHONY: help deps deps-lockfile get doctor analyze analyze-ci lint format format-docs format-docs-check format-check check
.PHONY: test test-sdk-machine test-playground coverage test-coverage test-sdk-coverage
.PHONY: build build-all build-android build-ios build-ios-no-codesign run run-ios run-android devices emulators
.PHONY: pana-install pana pub-publish-dry-run pub-publish-force
.PHONY: ios android

help:
	@printf "Usage:\n"
	@printf "  make test\n"
	@printf "  make build [android|ios]\n"
	@printf "  make run [android|ios]\n\n"
	@printf "Common targets:\n"
	@printf "  deps            Fetch workspace dependencies\n"
	@printf "  deps-lockfile   Fetch dependencies without changing pubspec.lock\n"
	@printf "  doctor          Show Flutter doctor output\n"
	@printf "  analyze         Analyze all packages\n"
	@printf "  analyze-ci      Analyze with Flutter CI flags\n"
	@printf "  format          Format Dart code\n"
	@printf "  format-check    Check Dart formatting\n"
	@printf "  test            Run tests in packages that have test/\n"
	@printf "  test-sdk-machine Run SDK tests and write machine JSON output\n"
	@printf "  test-playground Run playground tests\n"
	@printf "  coverage        Run tests with coverage\n"
	@printf "  test-sdk-coverage Run SDK tests with coverage\n"
	@printf "  check           Run format-check, analyze, and test\n\n"
	@printf "Playground targets:\n"
	@printf "  build           Build Android debug APK\n"
	@printf "  build android   Build Android debug APK\n"
	@printf "  build ios       Build iOS simulator debug app\n"
	@printf "  build-ios-no-codesign Build iOS debug app without code signing\n"
	@printf "  build-all       Build Android and iOS debug artifacts\n"
	@printf "  run             Run on iOS simulator\n"
	@printf "  run android     Run on Android emulator\n"
	@printf "  run ios         Run on iOS simulator\n"
	@printf "  devices         List connected devices\n"
	@printf "  emulators       List configured emulators\n\n"
	@printf "Publish targets:\n"
	@printf "  pana-install        Install pana globally\n"
	@printf "  pana                Run pana for the SDK package\n"
	@printf "  pub-publish-dry-run Run pub publish dry-run for the SDK package\n"
	@printf "  pub-publish-force   Publish the SDK package to pub.dev\n"

deps get:
	$(FLUTTER) pub get

deps-lockfile:
	$(FLUTTER) pub get --enforce-lockfile

doctor:
	$(FLUTTER) doctor -v

analyze lint:
	$(DART) analyze --fatal-infos .

analyze-ci:
	$(FLUTTER) analyze --fatal-infos --fatal-warnings

format:
	$(DART) format .
	$(MAKE) --no-print-directory format-docs

format-docs:
	npx -y prettier@3.6.2 --write "**/*.md"

format-docs-check:
	npx -y prettier@3.6.2 --check "**/*.md"

format-check:
	$(DART) format --output=none --set-exit-if-changed .
	$(MAKE) --no-print-directory format-docs-check

check: format-check analyze test

test:
	$(MELOS) exec --concurrency 1 --dir-exists=test -- "$(FLUTTER) test"

test-sdk-machine:
	mkdir -p $(TEST_RESULTS_DIR)
	cd $(SDK_DIR) && $(FLUTTER) test --machine > ../../$(TEST_RESULTS_DIR)/formbricks_flutter.json

test-playground:
	cd $(PLAYGROUND_DIR) && $(FLUTTER) test

coverage test-coverage:
	$(MELOS) exec --concurrency 1 --dir-exists=test -- "$(FLUTTER) test --coverage"

test-sdk-coverage:
	cd $(SDK_DIR) && $(FLUTTER) test --coverage

build:
	$(MAKE) --no-print-directory build-$(BUILD_PLATFORM)

build-all: build-android build-ios

build-android:
	cd $(PLAYGROUND_DIR) && $(FLUTTER) build apk --debug $(BUILD_ARGS)

build-ios:
	cd $(PLAYGROUND_DIR) && $(FLUTTER) build ios --simulator --debug $(BUILD_ARGS)

build-ios-no-codesign:
	cd $(PLAYGROUND_DIR) && $(FLUTTER) build ios --no-codesign --debug

run:
	./tool/run.sh $(RUN_PLATFORM) $(RUN_ARGS)

run-ios:
	./tool/run.sh ios $(RUN_ARGS)

run-android:
	./tool/run.sh android $(RUN_ARGS)

devices:
	$(FLUTTER) devices

emulators:
	$(FLUTTER) emulators

pana-install:
	$(DART) pub global activate pana

pana:
	$(DART) pub global run pana --no-warning --exit-code-threshold 30 $(SDK_DIR)

pub-publish-dry-run:
	cd $(SDK_DIR) && $(FLUTTER) pub publish --dry-run

pub-publish-force:
	cd $(SDK_DIR) && $(FLUTTER) pub publish --force

ifeq ($(firstword $(MAKECMDGOALS)),run)
ios android:
	@:
else ifeq ($(firstword $(MAKECMDGOALS)),build)
ios android:
	@:
else
ios: run-ios
android: run-android
endif
