# EdgeNoted

Modern SwiftUI macOS app, scaffolded with a feature-based layout and
lint/format/test automation wired up from the start.

## Quick start (SPM)

Build and run without ever opening Xcode:

```bash
make build       # compile with SwiftPM + create .app bundle
make run         # build (if needed) and launch the app
```

Or step by step with SwiftPM directly:

```bash
swift build -c release                              # compile
bash Scripts/build-app.sh                            # create .app bundle
open "Build/EdgeNoted.app"                          # launch it
```

## First-time setup

Install the command-line tooling:

```bash
brew install swiftlint periphery pre-commit
pre-commit install
```

XcodeGen is only needed for the XCTest UI-test target, the SwiftLint analyzer
check, or if you want an Xcode project. It can be used entirely from the
command line:

```bash
brew install xcodegen
xcodegen generate
open EdgeNoted.xcodeproj  # optional
```

## Common tasks

```bash
make build       # compile with SwiftPM + create .app bundle
make run         # build and launch the app
make format      # auto-format all Swift files
make lint        # run SwiftLint syntax rules (--strict)
make analyze     # run SwiftLint analyzer rules after a clean full compile
make dead-code   # scan every SwiftPM target for unused declarations (Periphery)
make test        # run unit + UI tests (requires xcodegen generate first)
make precommit   # format + lint + analysis + dead-code + test
```

## How it works

This project uses **two build systems** side by side:

| System | Manifest | Purpose |
|---|---|---|
| **SwiftPM** | `Package.swift` | Compile sources, run unit tests, produce executable |
| **XcodeGen** | `project.yml` | Generate `.xcodeproj` for UI tests, full Xcode integration |

A `Scripts/build-app.sh` script wraps `swift build` and assembles the
compiled binary into a proper `.app` bundle with `Info.plist`, compiled
asset catalogs, and resources — no Xcode required.

## Code quality

Regular SwiftLint rules run quickly from source with `make lint`. The
`unused_import` and `unused_declaration` analyzer rules require a clean,
full compile, so `make analyze` generates the Xcode project and captures an
`xcodebuild` compiler log before running `swiftlint analyze`. It never
requires the Xcode UI.

`make dead-code` runs Periphery. Periphery reads `Package.swift`, builds all
SwiftPM targets (including unit tests), and traverses their declaration graph
to find unused classes, functions, properties, and other declarations.

## Structure

```
EdgeNoted/
├── App/            # App entry point, AppState
├── Features/        # Feature-scoped views/view models
├── Models/          # Data models
├── Services/        # Persistence, networking, etc.
├── DesignSystem/     # Shared colors, components
└── Resources/        # Assets, Info.plist, entitlements
EdgeNotedTests/       # Swift Testing unit tests
EdgeNotedUITests/     # XCTest UI tests
Scripts/
├── build-app.sh              # macOS .app bundle builder (SPM-based)
└── swiftlint-analyze.sh      # clean Xcode CLI build + SwiftLint analyzer rules
.periphery.yml                # Periphery dead-code scan configuration
```

CI (`.github/workflows/ci.yml`) regenerates the Xcode project with XcodeGen,
then runs regular SwiftLint, compiled SwiftLint analyzer rules, Periphery,
a `swift format` check, and the full test suite on every PR.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
