// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "EasyTFDesktop", platforms: [.macOS(.v13)], products: [.executable(name: "EasyTFDesktop", targets: ["EasyTFDesktop"])], targets: [.executableTarget(name: "EasyTFDesktop"), .testTarget(name: "EasyTFDesktopTests", dependencies: ["EasyTFDesktop"])], swiftLanguageVersions: [.v5])
