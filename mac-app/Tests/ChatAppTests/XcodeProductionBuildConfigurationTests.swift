import Foundation
import XCTest

final class XcodeProductionBuildConfigurationTests: XCTestCase {
    func testPackageExposesReusableChatAppModuleAndPreservesSwiftRunProduct() throws {
        let package = try readMacAppFile("Package.swift")

        XCTAssertTrue(package.contains(".target(\n            name: \"ChatApp\""))
        XCTAssertTrue(package.contains(".library("))
        XCTAssertTrue(package.contains("targets: [\"ChatApp\"]"))
        XCTAssertTrue(package.contains(".executable(\n            name: \"ChatApp\""))
        XCTAssertTrue(package.contains(".executableTarget(\n            name: \"ChatAppRunner\""))
        XCTAssertTrue(package.contains("dependencies: [\"ChatApp\"]"))
    }

    func testXcodeProjectDefinesRunnableMacApplicationTarget() throws {
        let project = try readMacAppFile("ChatApp.xcodeproj/project.pbxproj")

        XCTAssertTrue(project.contains("productType = \"com.apple.product-type.application\""))
        XCTAssertTrue(project.contains("ChatApp.app"))
        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET = 13.0"))
        XCTAssertTrue(project.contains("SWIFT_VERSION = 6.0"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.testchatapp.ChatApp"))
        XCTAssertTrue(project.contains("productName = ChatAppCore"))
    }

    func testSharedSchemeRunsChatAppApplication() throws {
        let scheme = try readMacAppFile("ChatApp.xcodeproj/xcshareddata/xcschemes/ChatApp.xcscheme")

        XCTAssertTrue(scheme.contains("BuildableName = \"ChatApp.app\""))
        XCTAssertTrue(scheme.contains("BlueprintName = \"ChatApp\""))
        XCTAssertTrue(scheme.contains("<LaunchAction"))
        XCTAssertTrue(scheme.contains("<BuildableProductRunnable"))
    }

    func testReadmeDocumentsXcodeDebugAndReleaseBuilds() throws {
        let readme = try readRepositoryFile("README.md")

        XCTAssertTrue(readme.contains("open mac-app/ChatApp.xcodeproj"))
        XCTAssertTrue(readme.contains("xcodebuild -project ChatApp.xcodeproj -scheme ChatApp"))
        XCTAssertTrue(readme.contains("-configuration Release"))
        XCTAssertTrue(readme.contains("ChatApp.app"))
    }

    private func readMacAppFile(_ relativePath: String) throws -> String {
        try String(contentsOf: macAppRoot().appending(path: relativePath), encoding: .utf8)
    }

    private func readRepositoryFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appending(path: relativePath), encoding: .utf8)
    }

    private func macAppRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func repositoryRoot() -> URL {
        macAppRoot().deletingLastPathComponent()
    }
}
