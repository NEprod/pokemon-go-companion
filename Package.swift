// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GOAccountCompanion",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "GOCompanionDomain", targets: ["GOCompanionDomain"]),
        .library(name: "GOCompanionApplication", targets: ["GOCompanionApplication"]),
        .library(name: "GOCompanionKnowledge", targets: ["GOCompanionKnowledge"]),
        .library(name: "GOCompanionPersistence", targets: ["GOCompanionPersistence"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            providers: [.brew(["sqlite3"]), .apt(["libsqlite3-dev"])]
        ),
        .target(name: "GOCompanionDomain"),
        .target(
            name: "GOCompanionApplication",
            dependencies: ["GOCompanionDomain"]
        ),
        .target(
            name: "GOCompanionKnowledge",
            dependencies: ["GOCompanionDomain"]
        ),
        .target(
            name: "GOCompanionPersistence",
            dependencies: ["GOCompanionDomain", "GOCompanionApplication", "CSQLite"],
            resources: [.process("Migrations")]
        ),
        .testTarget(
            name: "GOCompanionTests",
            dependencies: [
                "GOCompanionDomain",
                "GOCompanionApplication",
                "GOCompanionKnowledge",
                "GOCompanionPersistence",
            ],
            resources: [.process("Fixtures")]
        ),
    ]
)
