// swift-tools-version:5.9
import PackageDescription

// AIToDoCore is pure Swift + Foundation (no UIKit/SwiftUI/FoundationModels), so the
// parser, memory, recall and habit logic are unit-tested on any platform, Linux included.
let package = Package(
    name: "AIToDo",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AIToDoCore", targets: ["AIToDoCore"])],
    targets: [
        .target(name: "AIToDoCore"),
        .testTarget(name: "AIToDoCoreTests", dependencies: ["AIToDoCore"]),
    ]
)
