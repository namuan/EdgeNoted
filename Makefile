.PHONY: generate format lint analyze dead-code test build run backup-notes precommit clean

generate:
	xcodegen generate

format:
	swift format --in-place --recursive EdgeNoted/ EdgeNotedTests/ EdgeNotedUITests/

lint:
	swiftlint lint --strict

analyze:
	@bash Scripts/swiftlint-analyze.sh

dead-code:
	periphery scan

test:
	xcodebuild test -project EdgeNoted.xcodeproj -scheme EdgeNoted -destination 'platform=macOS'

build:
	@bash Scripts/build-app.sh

# Build the app bundle, then (re)launch it. Any running instance is asked to
# quit first so the freshly built binary actually runs; the command fails if it
# does not exit within ~5s instead of silently activating a stale build.
run: build
	@pkill -TERM -x EdgeNoted 2>/dev/null || true; \
	for i in $$(seq 1 50); do pgrep -x EdgeNoted >/dev/null || break; sleep 0.1; done; \
	pgrep -x EdgeNoted >/dev/null && { echo "EdgeNoted did not quit in time" >&2; exit 1; }; \
	open "Build/EdgeNoted.app"

# Back up every Apple Notes note to ~/Documents/EdgeNoted Backup/<timestamp>/
backup-notes:
	@bash Scripts/backup-notes.sh

precommit: format lint analyze dead-code test

clean:
	rm -rf EdgeNoted.xcodeproj DerivedData TestResults Build .build
