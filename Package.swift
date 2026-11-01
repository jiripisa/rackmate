// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rackmate",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // The macOS app (bundle assembled by build.sh — see development_workflow.md §2).
        .executable(name: "Rackmate", targets: ["Rackmate"]),
        // App logic without UI — what `swift test` covers.
        .library(name: "RackmateCore", targets: ["RackmateCore"]),
        // Command-line probe for the audio layer.
        .executable(name: "rackmate-probe", targets: ["rackmate-probe"]),
    ],
    dependencies: [
        // Auto-update: the standard updater for apps outside the App Store;
        // EdDSA-signed appcast on GitHub Pages.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4"),
    ],
    targets: [
        .target(
            name: "RackmateCore",
            path: "Sources/RackmateCore"
        ),
        // Real-time render core in C.
        .target(
            name: "CRenderCore",
            path: "Sources/CRenderCore",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        // Audio Unit hosting and audio engine.
        .target(
            name: "RackmateAudio",
            dependencies: ["RackmateCore", "CRenderCore"],
            path: "Sources/RackmateAudio"
        ),
        // Test Audio Units for tests, and the safe ones for the debug app. Empty in a release.
        .target(
            name: "RackmateTestUnits",
            path: "Sources/RackmateTestUnits",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
            ]
        ),
        .executableTarget(
            name: "rackmate-probe",
            dependencies: ["RackmateAudio", "RackmateTestUnits", "CRenderCore"],
            path: "Sources/rackmate-probe"
        ),
        .executableTarget(
            name: "Rackmate",
            dependencies: [
                "RackmateCore",
                "RackmateAudio",
                "RackmateTestUnits",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Rackmate",
            linkerSettings: [
                // Embedded frameworks ship in Contents/Frameworks (build.sh).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "RackmateCoreTests",
            dependencies: ["RackmateCore"],
            path: "Tests/RackmateCoreTests"
        ),
        .testTarget(
            name: "RackmateAudioTests",
            dependencies: ["RackmateAudio", "RackmateTestUnits", "CRenderCore", "RackmateCore"],
            path: "Tests/RackmateAudioTests"
        ),
    ]
)
