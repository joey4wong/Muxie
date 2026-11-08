// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Muxie", platforms: [.macOS("26.0")], products: [.executable(name: "Muxie", targets: ["Muxie"])], targets: [.executableTarget(name: "Muxie", swiftSettings: [.swiftLanguageMode(.v5)])])
