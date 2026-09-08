# Third-party licenses

Sweep has **no third-party dependencies**. `Package.swift` declares a single
executable target and no package dependencies, and the source imports Apple
frameworks only.

## Apple frameworks

| Component | Used for | Terms |
| --- | --- | --- |
| SwiftUI | Views, app lifecycle | Apple SDK License Agreement |
| AppKit | Window, menu bar, `NSWorkspace`, `NSOpenPanel` | Apple SDK License Agreement |
| Foundation | File system access, localization, URLs | Apple SDK License Agreement |
| CoreGraphics | (transitive, via AppKit/SwiftUI) | Apple SDK License Agreement |

These frameworks ship with macOS and Xcode and are governed by the Apple
Developer Program License Agreement and the Xcode and Apple SDKs Agreement.
They are not redistributed with Sweep.

## SF Symbols

The app uses SF Symbols as vector glyph names (`shippingbox`, `trash`,
`hammer`, …). SF Symbols are provided by Apple and subject to the
[SF Symbols license terms](https://developer.apple.com/design/human-interface-guidelines/sf-symbols/)
included with the SF Symbols app. The symbols are referenced at runtime by
name and are not embedded or redistributed in this repository.

## Assets

Any image or icon placed in `docs/assets/` or `Support/Branding/` is original
work of the project authors and falls under the project's MIT license, unless
stated otherwise next to the file.

There is nothing else to list here. If a dependency is ever added, it must be
recorded in this file with its name, version, license, and upstream URL.
