# HTMLKeep Community

English · [简体中文](README.zh-CN.md) · [License](LICENSE)

HTMLKeep Community is the public source edition of HTMLKeep. It contains the
iOS / iPadOS and Android app source for local HTML file importing, browsing,
library management, search, widgets, recent deletion recovery, and local Agent
import workflows.

## Download

HTMLKeep Community is open source, so you can build and run the local apps
yourself to use the full feature set. You can also try the iOS / iPadOS app from
the App Store:

<a href="https://apps.apple.com/app/id6767142789"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="48"></a>

The Android app is not listed in an app store yet.

## License

HTMLKeep Community is licensed under the Mozilla Public License Version 2.0
(MPL-2.0). See `LICENSE`.

## iOS / iPadOS

Build the community simulator app with Xcode or `xcodebuild`:

```sh
xcodebuild -project ios/HTMLKeep.xcodeproj -scheme HTMLKeep -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The generated community project uses placeholder identifiers under
`com.htmlkeep.community`. Change them before distributing your own build.

## Android

Build from the Android project:

```sh
cd android
./gradlew assembleDebug
```
