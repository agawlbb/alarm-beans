# Alarm Beans working practices

## Development location

All development and image builds use VM-laptop. Follow the canonical VM/build,
checkout and deployment procedure in `/home/dev/projects/AGENTS.md`; older VPS
build commands and former laptop/VPS workspace paths in this repository are
superseded. The VPS only receives prepared artifacts for requested deployments.
Apple builds retain the existing macOS runner exception under that procedure.

## Repository workflow

Canonical repository: `agawlbb/alarm-beans`; default branch: `main`.
Follow the VM-wide working procedure in `/home/dev/projects/AGENTS.md`.
Use the existing checkout on `main`, one task at a time; no routine task
branches, extra worktrees or ownership claims. Commit and push completed source changes to `main`.
Use only relevant checks; do not repeat passing checks without a concrete reason.
Questions and status checks are read-only. Preserve unrelated work and credentials.
Deploy only when the user explicitly requests deployment. In every answer state
whether deployment and an app build are needed; do not automatically do either.

## Validation and releases

- Apple builds use the pinned Xcode and XcodeGen on GitHub Mac runners. `scripts/ci.sh` runs the shared Swift package tests, simulator builds, and unsigned archive checks. `scripts/watch-review.sh` captures the real Watch views and widget content using Debug-only fixtures; these do not establish physical-device alarm reliability.
- Preserve useful regression tests and the alarm scheduling, cancellation, migration, and runtime recovery behavior. Keep the UI minimal. The Watch settings panel is user-approved; change it only within a new authorized UI request.
- Inspect **all push triggers before every push**, including after a history rewrite. A normal `main` push currently runs both `ci.yml` and `testflight.yml`; the latter creates a signed distributable even though uploading defaults to false.
- A no-build cleanup must not dispatch workflows or create a distributable. After explicitly reporting the push-trigger mechanism, use GitHub's supported `[skip ci]` commit marker for that cleanup push; leave the workflow safeguards intact. Do not use this exception for unvalidated application changes.
- Upload/distribution requires the user's release authorization. The manual **Prepare signed build** workflow's `publish` flag enables upload, and the internal group's automatic distribution can then make the build available. Do not equate uploading with holding a build for later release. Coordinate updates around armed alarms when requested.
- Keep TestFlight build numbers unique. Preserve existing release tags and their targets; an ancestry cleanup is not a new app release. Build 1.0 (12) was released from original commit `63c79f343567b07d69e107b2e28d57d40ab743e5` after 39 tests passed.

## Recovery and secrets

- `.tools/` and `Config/Local.xcconfig` are local-only. Never publish or broadly copy ignored signing keys, certificates, profiles, credentials, or private runtime configuration. Back up tracked source and Git history without copying those assets.
- Delete only demonstrably obsolete or unrelated content after a verified recoverable backup. Preserve useful tests, release configuration, functional behavior, and all recovery archives.
- Rewrite ancestry only when explicitly authorized, after a quiescent coordination checkpoint and verified backups. Recheck live refs immediately before publishing and use an exact expected-SHA force-with-lease. Never blindly overwrite a changed remote or purge recovery data.
- Do not change branch protections, credentials, dependencies, hosting, or device installations as incidental cleanup. Security-sensitive protection changes require specific fresh user approval; report the minimal proposal while continuing unaffected work.
