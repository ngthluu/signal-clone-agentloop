import Foundation

struct Emoji: Identifiable, Equatable, Hashable {
    let character: String
    let name: String
    let keywords: [String]
    let category: EmojiCategory

    var id: String { character }
}

enum EmojiCategory: String, CaseIterable, Identifiable {
    case smileysAndPeople
    case animalsAndNature
    case foodAndDrink
    case activities
    case travelAndPlaces
    case objects
    case symbols
    case flags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smileysAndPeople:
            return "Smileys & People"
        case .animalsAndNature:
            return "Animals & Nature"
        case .foodAndDrink:
            return "Food & Drink"
        case .activities:
            return "Activities"
        case .travelAndPlaces:
            return "Travel & Places"
        case .objects:
            return "Objects"
        case .symbols:
            return "Symbols"
        case .flags:
            return "Flags"
        }
    }
}

enum EmojiCatalog {
    static let all: [Emoji] = [
        Emoji(character: "😀", name: "grinning face", keywords: ["happy", "smile", "joy"], category: .smileysAndPeople),
        Emoji(character: "😄", name: "beaming face with smiling eyes", keywords: ["happy", "laugh", "smile"], category: .smileysAndPeople),
        Emoji(character: "😂", name: "face with tears of joy", keywords: ["laugh", "funny", "cry"], category: .smileysAndPeople),
        Emoji(character: "😊", name: "smiling face with smiling eyes", keywords: ["blush", "happy", "warm"], category: .smileysAndPeople),
        Emoji(character: "😍", name: "smiling face with heart eyes", keywords: ["love", "crush", "heart"], category: .smileysAndPeople),
        Emoji(character: "🤔", name: "thinking face", keywords: ["consider", "question", "hmm"], category: .smileysAndPeople),
        Emoji(character: "👍🏽", name: "thumbs up medium skin tone", keywords: ["approve", "yes", "like"], category: .smileysAndPeople),
        Emoji(character: "👨‍👩‍👧", name: "family man woman girl", keywords: ["family", "parents", "child"], category: .smileysAndPeople),

        Emoji(character: "🐶", name: "dog face", keywords: ["pet", "puppy", "animal"], category: .animalsAndNature),
        Emoji(character: "🐱", name: "cat face", keywords: ["pet", "kitten", "animal"], category: .animalsAndNature),
        Emoji(character: "🦊", name: "fox", keywords: ["animal", "wild", "clever"], category: .animalsAndNature),
        Emoji(character: "🐼", name: "panda", keywords: ["bear", "animal", "cute"], category: .animalsAndNature),
        Emoji(character: "🦋", name: "butterfly", keywords: ["insect", "nature", "wings"], category: .animalsAndNature),
        Emoji(character: "🌸", name: "cherry blossom", keywords: ["flower", "spring", "nature"], category: .animalsAndNature),
        Emoji(character: "🌲", name: "evergreen tree", keywords: ["forest", "nature", "pine"], category: .animalsAndNature),
        Emoji(character: "🌊", name: "water wave", keywords: ["ocean", "sea", "surf"], category: .animalsAndNature),

        Emoji(character: "🍎", name: "red apple", keywords: ["fruit", "food", "snack"], category: .foodAndDrink),
        Emoji(character: "🍕", name: "pizza", keywords: ["food", "slice", "party"], category: .foodAndDrink),
        Emoji(character: "🍔", name: "hamburger", keywords: ["food", "burger", "meal"], category: .foodAndDrink),
        Emoji(character: "🍣", name: "sushi", keywords: ["food", "japanese", "fish"], category: .foodAndDrink),
        Emoji(character: "🍰", name: "shortcake", keywords: ["dessert", "cake", "sweet"], category: .foodAndDrink),
        Emoji(character: "☕️", name: "hot beverage", keywords: ["coffee", "tea", "drink"], category: .foodAndDrink),
        Emoji(character: "🍵", name: "teacup without handle", keywords: ["tea", "matcha", "drink"], category: .foodAndDrink),
        Emoji(character: "🥑", name: "avocado", keywords: ["fruit", "food", "green"], category: .foodAndDrink),

        Emoji(character: "⚽️", name: "soccer ball", keywords: ["sport", "football", "game"], category: .activities),
        Emoji(character: "🏀", name: "basketball", keywords: ["sport", "hoops", "game"], category: .activities),
        Emoji(character: "🎾", name: "tennis", keywords: ["sport", "racket", "game"], category: .activities),
        Emoji(character: "🎮", name: "video game", keywords: ["controller", "play", "gaming"], category: .activities),
        Emoji(character: "🎨", name: "artist palette", keywords: ["art", "paint", "creative"], category: .activities),
        Emoji(character: "🎤", name: "microphone", keywords: ["music", "sing", "karaoke"], category: .activities),
        Emoji(character: "🎉", name: "party popper", keywords: ["celebrate", "party", "confetti"], category: .activities),
        Emoji(character: "🏆", name: "trophy", keywords: ["win", "award", "success"], category: .activities),

        Emoji(character: "🚗", name: "automobile", keywords: ["car", "drive", "vehicle"], category: .travelAndPlaces),
        Emoji(character: "🚆", name: "train", keywords: ["rail", "transit", "travel"], category: .travelAndPlaces),
        Emoji(character: "✈️", name: "airplane", keywords: ["flight", "travel", "plane"], category: .travelAndPlaces),
        Emoji(character: "🚀", name: "rocket", keywords: ["launch", "space", "fast"], category: .travelAndPlaces),
        Emoji(character: "🏠", name: "house", keywords: ["home", "building", "place"], category: .travelAndPlaces),
        Emoji(character: "🏖️", name: "beach with umbrella", keywords: ["vacation", "sand", "travel"], category: .travelAndPlaces),
        Emoji(character: "⛰️", name: "mountain", keywords: ["hike", "nature", "place"], category: .travelAndPlaces),
        Emoji(character: "🌉", name: "bridge at night", keywords: ["city", "night", "place"], category: .travelAndPlaces),

        Emoji(character: "💡", name: "light bulb", keywords: ["idea", "bright", "object"], category: .objects),
        Emoji(character: "📱", name: "mobile phone", keywords: ["device", "phone", "text"], category: .objects),
        Emoji(character: "💻", name: "laptop", keywords: ["computer", "work", "device"], category: .objects),
        Emoji(character: "⌚️", name: "watch", keywords: ["time", "clock", "wearable"], category: .objects),
        Emoji(character: "📚", name: "books", keywords: ["study", "read", "library"], category: .objects),
        Emoji(character: "✏️", name: "pencil", keywords: ["write", "draw", "school"], category: .objects),
        Emoji(character: "🎁", name: "wrapped gift", keywords: ["present", "birthday", "surprise"], category: .objects),
        Emoji(character: "🔒", name: "locked", keywords: ["secure", "privacy", "key"], category: .objects),

        Emoji(character: "❤️", name: "red heart", keywords: ["heart", "love", "favorite"], category: .symbols),
        Emoji(character: "⭐️", name: "star", keywords: ["favorite", "rating", "sparkle"], category: .symbols),
        Emoji(character: "✅", name: "check mark button", keywords: ["done", "yes", "complete"], category: .symbols),
        Emoji(character: "❌", name: "cross mark", keywords: ["no", "cancel", "wrong"], category: .symbols),
        Emoji(character: "🔥", name: "fire", keywords: ["hot", "lit", "trend"], category: .symbols),
        Emoji(character: "✨", name: "sparkles", keywords: ["shine", "magic", "new"], category: .symbols),
        Emoji(character: "💯", name: "hundred points", keywords: ["perfect", "score", "complete"], category: .symbols),
        Emoji(character: "🔔", name: "bell", keywords: ["alert", "notification", "sound"], category: .symbols),

        Emoji(character: "🇺🇸", name: "flag United States", keywords: ["usa", "america", "flag"], category: .flags),
        Emoji(character: "🇯🇵", name: "flag Japan", keywords: ["japan", "jp", "flag"], category: .flags),
        Emoji(character: "🇻🇳", name: "flag Vietnam", keywords: ["vietnam", "vn", "flag"], category: .flags),
        Emoji(character: "🇬🇧", name: "flag United Kingdom", keywords: ["uk", "britain", "flag"], category: .flags),
        Emoji(character: "🇫🇷", name: "flag France", keywords: ["france", "fr", "flag"], category: .flags),
        Emoji(character: "🇩🇪", name: "flag Germany", keywords: ["germany", "de", "flag"], category: .flags),
        Emoji(character: "🇨🇦", name: "flag Canada", keywords: ["canada", "ca", "flag"], category: .flags),
        Emoji(character: "🇦🇺", name: "flag Australia", keywords: ["australia", "au", "flag"], category: .flags)
    ]

    static func emojis(in category: EmojiCategory) -> [Emoji] {
        all.filter { $0.category == category }
    }

    static func search(_ query: String) -> [Emoji] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return all
        }

        let lowercasedQuery = trimmedQuery.lowercased()
        return all.filter { emoji in
            emoji.name.lowercased().contains(lowercasedQuery) ||
                emoji.keywords.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
}
