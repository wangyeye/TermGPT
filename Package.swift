// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TermGPT", platforms: [.macOS(.v13)], products: [.executable(name: "TermGPT", targets: ["TermGPT"])], dependencies: [.package(path: "Vendor/SwiftTerm")], targets: [.executableTarget(name: "TermGPT", dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]), .testTarget(name: "TermGPTTests", dependencies: ["TermGPT"])])
