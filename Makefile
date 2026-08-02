.PHONY: generate format lint analyze dead-code test build run precommit clean

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

run: build
	@open "Build/EdgeNoted.app"

precommit: format lint analyze dead-code test

clean:
	rm -rf EdgeNoted.xcodeproj DerivedData TestResults Build .build
