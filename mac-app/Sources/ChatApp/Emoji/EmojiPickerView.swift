import SwiftUI

struct EmojiPickerView: View {
    @ObservedObject var model: MessageComposerModel
    private let columns = [
        GridItem(.adaptive(minimum: 36), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EmojiCategory.allCases) { category in
                        Button(category.title) {
                            model.selectedCategory = category
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(model.selectedCategory == category ? .accentColor : .secondary)
                    }
                }
                .padding(.bottom, 2)
            }

            TextField("Search emoji", text: $model.searchQuery)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.filteredEmojis) { emoji in
                        Button {
                            model.insert(emoji: emoji.character)
                        } label: {
                            Text(emoji.character)
                                .font(.system(size: 24))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .help(emoji.name)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 150, maxHeight: 220)
        }
        .padding(12)
        .frame(width: 320)
    }
}
