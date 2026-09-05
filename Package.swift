// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "AngerRate", platforms: [.macOS(.v13)], products: [.library(name: "AngerCore", targets: ["AngerCore"]), .executable(name: "AngerRate", targets: ["AngerRate"])], targets: [.target(name: "AngerCore"), .executableTarget(name: "AngerRate", dependencies: ["AngerCore"]), .testTarget(name: "AngerCoreTests", dependencies: ["AngerCore"])])
