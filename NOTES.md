### TestSatochip — Build, Install, and Launch on iPhone (command line)

This project builds an iOS app target named `TestSatochip` with bundle id `com.gammastream.app.TestSatochip`.

#### Prerequisites
- Xcode 15+ installed (`xcodebuild -version` to verify)
- Command Line Tools selected in Xcode Preferences
- A physical iPhone connected, unlocked, and trusted
- Valid signing team/profiles configured for this project

#### Clean build (optional)
```bash
cd /Users/i830671/git/TestSatochip-iOS
xcrun xcodebuild -project TestSatochip.xcodeproj \
  -scheme TestSatochip \
  -configuration Debug \
  -sdk iphoneos \
  -derivedDataPath build \
  clean
```

#### Build and run directly to a connected iPhone
Identify your device destination:
```bash
xcrun xcodebuild -project TestSatochip.xcodeproj -scheme TestSatochip -showdestinations | cat
```

Build to the device (replace DEVICE_NAME with your device’s name):
```bash
xcrun xcodebuild -project TestSatochip.xcodeproj \
  -scheme TestSatochip \
  -configuration Debug \
  -destination 'platform=iOS,name=DEVICE_NAME' \
  build
```

#### Alternative: install using ios-deploy
If you prefer installing the built .app manually:
```bash
# Build for device (requires proper signing)
xcrun xcodebuild -project TestSatochip.xcodeproj \
  -scheme TestSatochip \
  -configuration Debug \
  -sdk iphoneos \
  -derivedDataPath build \
  build

# Then install & launch (requires: npm i -g ios-deploy)
ios-deploy --bundle build/Build/Products/Debug-iphoneos/TestSatochip.app --justlaunch
```

### Swift Package resolution tips
- This project references a local package at `../../git/SatochipSwift`.
- If package resolution fails or paths changed:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
xcrun xcodebuild -resolvePackageDependencies -project TestSatochip.xcodeproj -scheme TestSatochip
```

### Common troubleshooting
- Code signing errors: ensure the `DEVELOPMENT_TEAM` and provisioning are valid and the bundle id `com.gammastream.app.TestSatochip` is registered in Apple Developer.


