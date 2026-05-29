# HTMLKeep Community

[English](README.md) · 简体中文 · [License](LICENSE)

HTMLKeep Community 是随手网页的公开源码版本。它包含 iOS / iPadOS
和 Android App 源码，支持本地 HTML 文件导入、浏览、网页库管理、搜索、
桌面小组件、最近删除恢复，以及本地 Agent 导入工作流。

## 下载

HTMLKeep Community 是开源项目，你可以自行构建并在本地部署 App，以使用
完整功能；也可以通过 App Store 下载 iOS / iPadOS 版本进行试用：

<a href="https://apps.apple.com/app/id6767142789"><img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="在 App Store 下载" height="48"></a>

安卓版目前还没有上架。

## 许可

HTMLKeep Community 使用 Mozilla Public License Version 2.0（MPL-2.0）
授权。详见 `LICENSE`。

## iOS / iPadOS

可以用 Xcode 或 `xcodebuild` 构建社区版模拟器 App：

```sh
xcodebuild -project ios/HTMLKeep.xcodeproj -scheme HTMLKeep -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

生成的社区版项目默认使用 `com.htmlkeep.community` 下的占位标识。
如果你要分发自己的构建，请先替换这些标识。

## Android

从 Android 项目构建：

```sh
cd android
./gradlew assembleDebug
```
