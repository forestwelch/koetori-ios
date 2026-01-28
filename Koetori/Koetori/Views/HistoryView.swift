import SwiftUI

struct HistoryView: View {
    @StateObject private var historyStore = HistoryStore.shared
    @State private var selectedItem: HistoryItem?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Group {
            if historyStore.items.isEmpty {
                Text("No memos yet")
                    .font(.system(size: 17))
                    .foregroundColor(.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(historyStore.items) { item in
                        Button {
                            selectedItem = item
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.response.transcript)
                                    .font(.system(size: 15))
                                    .foregroundColor(.textPrimary)
                                    .lineLimit(2)
                                HStack {
                                    Text(dateFormatter.string(from: item.receivedAt))
                                        .font(.system(size: 13))
                                        .foregroundColor(.textMuted)
                                    Text("•")
                                        .foregroundColor(.textMuted)
                                    Text(item.source.rawValue.uppercased())
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.textMuted)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.bgPrimary)
        .preferredColorScheme(.dark)
        .sheet(item: $selectedItem) { item in
            ResultsView(response: item.response)
        }
    }
}
