# Android Platform Reference

## Prerequisites
- Android device with USB debugging enabled
- `adb` in PATH (Android SDK Platform-Tools)
- Device running Android 12+ (API 31+)
- BLUETOOTH_SCAN, BLUETOOTH_CONNECT permissions granted at runtime

## Build
```
cd packages/butane_harness && flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`

## Install
```
adb -s <serial> install -r <apk>
```

## Launch
```
adb -s <serial> shell am start \
  -n "com.nicospencer.butane_harness/.MainActivity" \
  --es ROLE <role> \
  --es WS_PORT <port>
```

## mDNS (NSD)
Android uses NsdManager for mDNS. The harness advertises via
`_butane-harness._tcp` the same as other platforms.

## Troubleshooting
- **Device not found**: Check `adb devices` output
- **Permission denied**: Ensure USB debugging is enabled in Developer Options
- **BLE not working**: Check BLE permissions in app settings, ensure Bluetooth is on
- **mDNS not advertising**: NSD requires the device to be on the same network subnet
