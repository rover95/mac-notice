# Repository Guidelines

## Project Structure & Module Organization
mac-notice/ hosts the SwiftUI code. `mac_noticeApp.swift` configures the main scene; avoid placing business logic there. Keep feature views inside `mac-notice/Views/` and share reusable modifiers, colors, or helpers in `mac-notice/Components/`. Assets such as app icons and named colors belong in `mac-notice/Assets.xcassets` (e.g., `SecondaryBackground`). Mirror future testable logic under `mac-noticeTests/` once added.

## Build, Test, and Development Commands
- `open mac-notice/mac-notice.xcodeproj` — launch the project in Xcode with the `mac-notice` scheme for live previews.
- `xcodebuild -scheme mac-notice build` — run a CI-style build; append `-quiet` in scripts to curb log noise.
- `xcodebuild -scheme mac-notice test -destination "platform=macOS"` — execute XCTest bundles when the test target exists.
Store automation scripts in `build/` if needed and keep derived data outside the repo.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: types use PascalCase (`NoticeBannerView`), methods and stored properties are camelCase, and shared constants use upper camel or SCREAMING_SNAKE when static. Indent with 4 spaces and group related modifiers. Prefer immutable `let` bindings, and keep view builders slim by extracting helpers. Re-indent files with Xcode (⌃I) before committing; apply `swift-format` once configured.

## Testing Guidelines
Use XCTest for view models and logic. Name suites after the source file plus `Tests` (e.g., `ContentViewTests`). Write fast, deterministic tests that set up fixtures in `setUp()` and clean in `tearDown()`. Run `xcodebuild test` locally prior to pushing and capture failures with screenshots or logs when UI assertions are involved.

## Commit & Pull Request Guidelines
Author concise, imperative commit subjects such as "Add banner dismissal state." Consolidate fixups locally and reference issues in the body (`Closes #123`). Pull requests should summarize intent, enumerate manual or automated tests, and attach screenshots or recordings for UI-facing changes. Mention configuration updates or new environment variables explicitly.

## Security & Configuration Tips
Never commit signing identities, API tokens, or machine-specific settings. Prefer `.xcconfig` overlays and document required secrets in the PR description. Scrub personal data from logs before sharing build artifacts.
