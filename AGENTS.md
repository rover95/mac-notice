# Repository Guidelines

## Project Structure & Module Organization
- mac-notice/mac_noticeApp.swift boots the SwiftUI app and should remain focused on scene configuration.
- mac-notice/ContentView.swift holds the primary UI; add new views in mac-notice/Views/ and share reusable modifiers in mac-notice/Components/ when the project grows.
- Store assets such as app icons or color sets in mac-notice/Assets.xcassets and keep naming aligned with their usage (e.g., `SecondaryBackground`).

## Build, Test, and Development Commands
- `open mac-notice/mac-notice.xcodeproj` launches the workspace in Xcode; use the default `mac-notice` scheme for editing and previews.
- `xcodebuild -scheme mac-notice build` performs a CI-friendly build; add `-quiet` during automation to trim log noise.
- `xcodebuild -scheme mac-notice test -destination "platform=macOS"` runs unit tests once a test target is present; mirror CI settings locally.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines: PascalCase for types (`NoticeBannerView`), camelCase for functions and properties, and uppercase for static constants when appropriate.
- Keep indentation at 4 spaces, prefer `let` over `var`, and group related view modifiers for readability.
- Run Xcode’s `Editor > Structure > Re-Indent` (⌃I) before committing; apply `swift-format` if introduced to keep style consistent across contributors.

## Testing Guidelines
- Add a `mac-noticeTests` target under mac-notice/ whenever logic exceeds simple view rendering; mirror source file names with a `Tests` suffix (`ContentViewTests`).
- Aim for fast, deterministic tests using XCTest; favor view model coverage and snapshot checks for SwiftUI components.
- Execute `xcodebuild test` locally before opening a pull request and ensure new features ship with at least one new assertion.

## Commit & Pull Request Guidelines
- Write concise, imperative commit summaries (e.g., "Add banner dismissal state"), mirroring the existing history.
- Squash incidental fixups before review, link tickets in the body (`Closes #123`), and mention affected areas.
- Pull requests should outline intent, testing performed, and attach screenshots or screen recordings for UI changes.

## Configuration & Secrets
- Do not commit personal signing certificates, API tokens, or machine-specific settings; prefer `.xcconfig` overlays ignored by git.
- Document required environment variables in the pull request and scrub sensitive data from captured logs before sharing.
