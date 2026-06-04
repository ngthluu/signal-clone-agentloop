import XCTest
@testable import ChatApp

final class EmojiCatalogTests: XCTestCase {
    func testCatalogIsNonEmptyAndEveryCategoryHasEntries() {
        XCTAssertFalse(EmojiCatalog.all.isEmpty)

        for category in EmojiCategory.allCases {
            XCTAssertFalse(EmojiCatalog.emojis(in: category).isEmpty, "\(category.title) should have emojis")
        }
    }

    func testEveryEmojiHasMetadataAndIsFiledInItsCategory() {
        for emoji in EmojiCatalog.all {
            XCTAssertFalse(emoji.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(emoji.keywords.isEmpty)
            XCTAssertTrue(EmojiCatalog.emojis(in: emoji.category).contains(emoji))
        }
    }

    func testSearchMatchesHeartByNameOrKeyword() {
        XCTAssertTrue(EmojiCatalog.search("heart").contains { $0.character == "❤️" })
    }

    func testSearchMatchesKeywordThatIsNotPartOfName() throws {
        let result = try XCTUnwrap(EmojiCatalog.search("happy").first { $0.character == "😀" })

        XCTAssertFalse(result.name.localizedCaseInsensitiveContains("happy"))
        XCTAssertTrue(result.keywords.contains { $0.localizedCaseInsensitiveContains("happy") })
    }

    func testSearchIsCaseInsensitive() {
        XCTAssertEqual(Set(EmojiCatalog.search("SMILE")), Set(EmojiCatalog.search("smile")))
    }

    func testEmptySearchReturnsAllEmojis() {
        XCTAssertEqual(EmojiCatalog.search(""), EmojiCatalog.all)
        XCTAssertEqual(EmojiCatalog.search("   \n\t"), EmojiCatalog.all)
    }

    func testNonsenseSearchReturnsNoEmojis() {
        XCTAssertEqual(EmojiCatalog.search("zzqq-nonsense"), [])
    }

    func testEmojiCharactersAreUnique() {
        XCTAssertEqual(Set(EmojiCatalog.all.map(\.character)).count, EmojiCatalog.all.count)
    }

    func testCatalogIncludesMultiScalarExamples() {
        let characters = Set(EmojiCatalog.all.map(\.character))

        XCTAssertTrue(characters.contains("👨‍👩‍👧"))
        XCTAssertTrue(characters.contains("👍🏽"))
        XCTAssertTrue(characters.contains("🇯🇵"))
    }
}
