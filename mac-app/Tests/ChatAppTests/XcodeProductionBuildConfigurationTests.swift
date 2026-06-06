import Foundation
import XCTest

final class XcodeProductionBuildConfigurationTests: XCTestCase {
    func testPackageExposesChatAppCoreLibraryAndChatAppRunnerExecutable() throws {
        let package = try readMacAppFile("Package.swift")
        let products = try section(in: package, from: "products: [", to: "\n    targets: [")
        let targets = try section(in: package, from: "\n    targets: [", to: "\n    ]\n)")

        XCTAssertTrue(products.contains("""
        .library(
                    name: "ChatAppCore",
                    targets: ["ChatApp"]
                )
        """))
        XCTAssertTrue(products.contains("""
        .executable(
                    name: "ChatAppRunner",
                    targets: ["ChatAppRunner"]
                )
        """))
        XCTAssertEqual(occurrenceCount(of: ".executable(", in: products), 1)
        XCTAssertFalse(products.contains("name: \"ChatApp\""))

        XCTAssertTrue(targets.contains("""
        .target(
                    name: "ChatApp"
                )
        """))
        XCTAssertTrue(targets.contains("""
        .executableTarget(
                    name: "ChatAppRunner",
                    dependencies: ["ChatApp"]
                )
        """))
    }

    func testXcodeProjectDefinesOnlyNativeChatAppApplicationProduct() throws {
        let project = try readMacAppFile("ChatApp.xcodeproj/project.pbxproj")

        XCTAssertEqual(occurrenceCount(of: "path = ChatApp.app;", in: project), 1)
        XCTAssertEqual(occurrenceCount(of: "productType = \"com.apple.product-type.application\";", in: project), 1)
        XCTAssertEqual(occurrenceCount(of: "explicitFileType = wrapper.application", in: project), 1)

        XCTAssertTrue(project.contains("MACOSX_DEPLOYMENT_TARGET = 13.0"))
        XCTAssertTrue(project.contains("SWIFT_VERSION = 6.0"))
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.testchatapp.ChatApp"))
    }

    func testXcodeProjectLinksCoreLibraryAndNotRunnerExecutable() throws {
        let project = try readMacAppFile("ChatApp.xcodeproj/project.pbxproj")
        let frameworks = try section(in: project, from: "/* Begin PBXFrameworksBuildPhase section */", to: "/* End PBXFrameworksBuildPhase section */")
        let packageProducts = try section(in: project, from: "/* Begin XCSwiftPackageProductDependency section */", to: "/* End XCSwiftPackageProductDependency section */")

        XCTAssertTrue(frameworks.contains("ChatAppCore in Frameworks"))
        XCTAssertFalse(frameworks.contains("ChatAppRunner"))

        XCTAssertTrue(project.contains("productName = ChatAppCore"))
        XCTAssertTrue(packageProducts.contains("productName = ChatAppCore;"))
        XCTAssertFalse(packageProducts.contains("productName = ChatAppRunner;"))
    }

    func testSharedSchemeBuildsAndLaunchesNativeChatAppApplication() throws {
        let scheme = try readMacAppFile("ChatApp.xcodeproj/xcshareddata/xcschemes/ChatApp.xcscheme")
        let buildAction = try section(in: scheme, from: "<BuildAction", to: "</BuildAction>")
        let launchAction = try section(in: scheme, from: "<LaunchAction", to: "</LaunchAction>")

        assertBuildableReference(in: buildAction)
        assertBuildableReference(in: launchAction)
        XCTAssertTrue(launchAction.contains("<BuildableProductRunnable"))
        XCTAssertFalse(scheme.contains("BlueprintName = \"ChatAppRunner\""))
    }

    func testReadmeDocumentsSwiftRunnerXcodeSchemeAndReleaseBundlePath() throws {
        let readme = try readRepositoryFile("README.md")

        XCTAssertTrue(readme.contains("swift run ChatAppRunner"))
        XCTAssertFalse(readme.contains("swift run ChatApp\n"))
        XCTAssertTrue(readme.contains("open mac-app/ChatApp.xcodeproj"))
        XCTAssertTrue(readme.contains("Select the shared `ChatApp` scheme"))
        XCTAssertTrue(readme.contains("xcodebuild -project ChatApp.xcodeproj -scheme ChatApp -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/chatapp-xcode-release build"))
        XCTAssertTrue(readme.contains("/tmp/chatapp-xcode-release/Build/Products/Release/ChatApp.app"))
    }

    private func assertBuildableReference(in section: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(section.contains("BuildableName = \"ChatApp.app\""), file: file, line: line)
        XCTAssertTrue(section.contains("BlueprintName = \"ChatApp\""), file: file, line: line)
        XCTAssertTrue(section.contains("ReferencedContainer = \"container:ChatApp.xcodeproj\""), file: file, line: line)
    }

    private func section(in text: String, from start: String, to end: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        guard let startRange = text.range(of: start) else {
            XCTFail("Missing section start: \(start)", file: file, line: line)
            throw SectionError.missingStart
        }
        guard let endRange = text[startRange.upperBound...].range(of: end) else {
            XCTFail("Missing section end: \(end)", file: file, line: line)
            throw SectionError.missingEnd
        }
        return String(text[startRange.lowerBound..<endRange.upperBound])
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
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

    private enum SectionError: Error {
        case missingStart
        case missingEnd
    }
}
