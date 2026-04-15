# Platform: macOS
- Pre-grant Bluetooth via `tccutil reset Bluetooth com.nicospencer.butaneHarness` if TCC prompts stall the app.
- Built bundle: `packages/butane_harness/build/macos/Build/Products/Release/butane_harness.app`.
- Launch: `open -n "<bundle>" --env ROLE=central --env WS_PORT=19100`.
- Cleanup: `killall butane_harness 2>/dev/null || true`.
