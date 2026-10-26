# Coucou build, test and install (macOS app; `make windows` for Tauri). Targets: see README → Build.

XCODEBUILD ?= xcodebuild
DERIVED    ?= $(CURDIR)/NotchBuddy/build/DerivedData
PROJECT    := NotchBuddy

# Same list as .github/workflows/build.yml.
TESTS := screen-geometry claude-hooks display-choice session-registry approval-queue \
	flow-keys flow-text notetaker whatsapp mac-update whats-new-mac claude-desktop-chat \
	desktop-mochi auto-close provider-endpoints island-hover voice-wake voice-vad voice-island \
	voice-intent voice-entity voice-query voice-runner voice-conversation voice-gender \
	voice-spotter-gen voice-wake-blocked turn-end-policy ask-question chat-parsing \
	claude-host claude-response claude-settings conversation-context diff-engine \
	github-activity github-pulse pill-colors plan-gauge safe-links terminal-target wardrobe

.PHONY: all project build appstore release test localization install windows clean

all: build appstore test

project:
	@command -v xcodegen >/dev/null || { echo "xcodegen missing: brew install xcodegen"; exit 1; }
	cd $(PROJECT) && xcodegen -q

build: project
	@echo "[coucou] Debug build (unsigned)"
	cd $(PROJECT) && $(XCODEBUILD) -scheme NotchBuddy -configuration Debug \
		-derivedDataPath "$(DERIVED)" -quiet build

# Unsigned: the App Store target otherwise asks for a Mac Development certificate.
appstore: project
	@echo "[coucou] App Store Debug build (unsigned)"
	cd $(PROJECT) && $(XCODEBUILD) -scheme CoucouAppStore -configuration Debug \
		-derivedDataPath "$(DERIVED)" -quiet \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build

release: project
	@echo "[coucou] Release build (Developer ID)"
	cd $(PROJECT) && $(XCODEBUILD) -scheme NotchBuddy -configuration Release \
		-derivedDataPath "$(DERIVED)" -quiet build

test: localization
	@set -e; for t in $(TESTS); do \
	  echo "[coucou] test-$$t"; bash scripts/test-$$t.sh >/dev/null || { echo "FAIL: test-$$t"; exit 1; }; \
	done; echo "[coucou] all tests passed"

localization:
	python3 scripts/test-localization.py

# Signed DebugCloud build into /Applications, permissions kept.
install:
	./scripts/dev-install.sh

windows:
	cd windows && npm install && npm run tauri dev

clean:
	rm -rf "$(DERIVED)"
