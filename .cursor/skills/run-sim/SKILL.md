---
name: run-sim
description: >-
  Build the Owed iOS app and launch it on the iOS Simulator, then show a
  screenshot in chat. Use when the user asks to run, build, launch, or see
  the app on the simulator.
disable-model-invocation: false
---

# Run Owed on the iOS Simulator

Build, install, and launch the Owed app on the simulator, then present a
screenshot in chat so the user sees the result without leaving Cursor.

## Project facts

- Project: `/Users/dj/Documents/Owed/Owed.xcodeproj`, scheme `Owed`
- Bundle id: `AvaResearchLLC.Owed`
- Preferred simulator: iPhone 17 Pro (any available iPhone is fine)

## Steps

1. **Prefer the XcodeBuildMCP server** (`project-0-Owed-XcodeBuildMCP`):
   - Call `session_show_defaults`; if project/scheme/simulator aren't set,
     call `session_set_defaults` with the project facts above.
   - Call `build_run_sim` (empty arguments once defaults are set) — it
     builds, boots the simulator, opens Simulator.app, installs, and
     launches in one call, and returns build + runtime log paths.
   - Call the `screenshot` tool and include the image in the reply.
2. If MCP is unavailable, fall back to the shell (needs `required_permissions: ["all"]`
   because the sandbox blocks CoreSimulatorService):

```bash
cd /Users/dj/Documents/Owed
xcodebuild -project Owed.xcodeproj -scheme Owed \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/OwedSimBuild build
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
xcrun simctl install booted /tmp/OwedSimBuild/Build/Products/Debug-iphonesimulator/Owed.app
xcrun simctl launch booted AvaResearchLLC.Owed
```

3. **Verify and show the result.** Wait ~3 seconds after launch, capture a
   screenshot, and embed it in the reply:

```bash
xcrun simctl io booted screenshot /tmp/owed-sim.png
```

4. If the build fails, report the compiler errors (file, line, message)
   directly — never ask the user to paste logs.

## Notes

- The bundled feed is `Owed/Resources/SettlementFeed.json`; the app also
  fetches the live copy from the GitHub repo's `main` branch on launch.
- Screenshot lands in `/tmp/owed-sim.png`; embed it with a markdown image.
