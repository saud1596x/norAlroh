// swift-tools-version: 5.10
import PackageDescription

let package = Package(name: "NoorVAD", products: [
    .library(name: "CNoorVAD", targets: ["CNoorVAD"])
], targets: [
    .target(name: "CNoorVAD", exclude: ["LICENSE", "PATENTS", "AUTHORS"],
        publicHeadersPath: "include", cSettings: [.headerSearchPath("src")])
])
