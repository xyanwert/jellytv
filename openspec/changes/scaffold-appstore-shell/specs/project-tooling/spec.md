# project-tooling

## ADDED Requirements

### Requirement: Deterministic project generation
`project.yml` SHALL be the single source of truth for the Xcode project; `JellyTV.xcodeproj` SHALL be gitignored and reproducible at any time with `xcodegen generate`.

#### Scenario: Fresh clone produces a working project
- **WHEN** `xcodegen generate` is run in a clean checkout containing no `.xcodeproj`
- **THEN** `JellyTV.xcodeproj` is generated and both app schemes build successfully

### Requirement: Bootstrap script
A `Scripts/bootstrap.sh` SHALL verify (and where possible install via Homebrew) required tools — XcodeGen, fastlane — then generate icons and the Xcode project, so a fresh clone reaches "openable in Xcode" with one command.

#### Scenario: One-command setup
- **WHEN** `Scripts/bootstrap.sh` runs on a machine with Xcode and Homebrew installed
- **THEN** it exits 0 leaving a generated `JellyTV.xcodeproj`, populated asset catalogs, and a report of any tools it installed

### Requirement: Shared JellyTVKit package
A local Swift package `Packages/JellyTVKit` SHALL be linked by both app targets and expose at least one symbol consumed by both, with a passing unit-test target.

#### Scenario: Package tests pass and both apps link it
- **WHEN** `swift test` runs in `Packages/JellyTVKit` and both app schemes are built
- **THEN** the package tests pass and both apps compile against a `JellyTVKit` symbol

### Requirement: Reproducible icon generation
`Scripts/generate-icons.swift` SHALL regenerate every branding asset (tvOS layered icons, top-shelf images, iOS icon) and their asset-catalog JSON from code, with no external dependencies beyond macOS system frameworks.

#### Scenario: Regeneration is idempotent and valid
- **WHEN** the icon script is run twice in a row and the project is rebuilt
- **THEN** the second run produces identical output (idempotent) and the build's asset compilation reports no icon errors

### Requirement: Repo hygiene and MCP tooling
The repo SHALL contain a Swift/Xcode-appropriate `.gitignore` (excluding `.xcodeproj`, DerivedData, `fastlane/.env`, API keys), a `README.md` documenting the bootstrap/build/release workflow, a license file, a default branch named `main`, and a project-scoped `.mcp.json` registering XcodeBuildMCP.

#### Scenario: Working tree stays clean after a build
- **WHEN** the project is generated, built, and a fastlane lane is run
- **THEN** `git status` shows no untracked build products, generated projects, or credential files

#### Scenario: MCP server available in a fresh session
- **WHEN** a new Claude Code session starts in this repo and `.mcp.json` servers are approved
- **THEN** XcodeBuildMCP tools are available for building and simulator control
