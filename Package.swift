// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "GOCompanionDomain", targets: ["GOCompanionDomain"]),
    .library(name: "GOCompanionApplication", targets: ["GOCompanionApplication"]),
    .library(name: "GOCompanionKnowledge", targets: ["GOCompanionKnowledge"]),
    .library(name: "GOCompanionPersistence", targets: ["GOCompanionPersistence"]),
]

var targets: [Target] = [
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
        dependencies: [
            "GOCompanionDomain", "GOCompanionApplication", "GOCompanionKnowledge", "CSQLite",
        ],
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

#if os(macOS)
    products += [
        .library(name: "GOCompanionCapture", targets: ["GOCompanionCapture"]),
        .library(name: "GOCompanionScreenAnalysis", targets: ["GOCompanionScreenAnalysis"]),
        .library(name: "GOCompanionExtraction", targets: ["GOCompanionExtraction"]),
        .library(name: "MacRecognitionAdapter", targets: ["MacRecognitionAdapter"]),
        .library(name: "MacCaptureAdapter", targets: ["MacCaptureAdapter"]),
        .executable(name: "CaptureDiagnostic", targets: ["CaptureDiagnostic"]),
    ]
    targets += [
        .target(name: "GOCompanionCapture"),
        .target(name: "GOCompanionScreenAnalysis", dependencies: ["GOCompanionCapture"]),
        .target(name: "GOCompanionExtraction", dependencies: ["GOCompanionCapture", "GOCompanionScreenAnalysis"]),
        .target(name: "MacRecognitionAdapter", dependencies: ["GOCompanionCapture", "GOCompanionExtraction"]),
        .target(name: "MacCaptureAdapter", dependencies: ["GOCompanionCapture"]),
        .executableTarget(
            name: "CaptureDiagnostic",
            dependencies: [
                "GOCompanionCapture", "GOCompanionScreenAnalysis", "GOCompanionExtraction", "MacCaptureAdapter",
                "MacRecognitionAdapter",
            ]
        ),
        .testTarget(
            name: "CaptureDiagnosticTests",
            dependencies: [
                "GOCompanionCapture", "GOCompanionScreenAnalysis", "GOCompanionExtraction", "MacCaptureAdapter",
                "MacRecognitionAdapter",
            ],
            exclude: ["Fixtures"]
        ),
    ]
#endif

let package = Package(
    name: "GOAccountCompanion",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: products,
    targets: targets
)
