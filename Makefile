.PHONY: format lint dead-code test build run backup-notes precommit clean

format:
	swift format --in-place --recursive EdgeNoted/ EdgeNotedTests/

lint:
	swiftlint lint --strict

dead-code:
	periphery scan

test:
	swift test

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

precommit: format lint dead-code test

clean:
	rm -rf DerivedData TestResults Build .build
