import SwiftUI

struct HistoryView: View {
    @State private var records: [QueryRecord] = []
    @State private var query = ""
    @State private var confirmClear = false

    private var filtered: [QueryRecord] {
        guard !query.isEmpty else { return records }
        return records.filter { ($0.inputText ?? "截图查询").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索历史", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button(confirmClear ? "确认清除全部？" : "清除全部") {
                    if confirmClear {
                        DataStore.deleteAllQueries()
                        reload()
                    }
                    confirmClear.toggle()
                }
                .disabled(records.isEmpty)
                .foregroundColor(confirmClear ? .red : nil)
            }
            .padding(10)
            .onChange(of: query) { _ in confirmClear = false }
            Divider()
            if filtered.isEmpty {
                Text("暂无历史记录").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered, id: \.id) { r in
                    row(r)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 580, height: 500)
        .onAppear { reload() }
    }

    private func reload() {
        records = DataStore.allQueries()
    }

    private func row(_ r: QueryRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(kindBadge(r.inputKind))
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
            if let thumb = r.thumbnail, let img = NSImage(data: thumb) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 33)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(preview(r.inputText))
                    .font(.callout)
                    .lineLimit(1)
                Text("\(dateStr(r.createdAt)) · \(r.model)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { replay(r) }
    }

    private func preview(_ text: String?) -> String {
        let t = text ?? "截图查询"
        return t.count > 40 ? String(t.prefix(40)) + "…" : t // product §7：40 字截断
    }

    private func kindBadge(_ kind: String) -> String {
        switch kind {
        case QueryKind.word.rawValue: return "词"
        case QueryKind.sentence.rawValue: return "句"
        case QueryKind.paragraph.rawValue: return "段"
        case QueryKind.article.rawValue: return "读"
        case QueryKind.screenshotExplain.rawValue, QueryKind.screenshotWordAt.rawValue: return "图"
        default: return "?"
        }
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    private func replay(_ r: QueryRecord) {
        if r.inputKind == QueryKind.article.rawValue {
            WindowManager.shared.showReader(text: r.inputText ?? "")
            return
        }
        let thumb = r.thumbnail.flatMap { NSImage(data: $0) }
        SessionCoordinator.shared.replay(recordKind: r.inputKind, inputText: r.inputText, response: r.responseMarkdown, thumbnail: thumb)
    }
}
