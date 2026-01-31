import Foundation
import SwiftUI
import UIKit

/// In-app debug logger that stores logs for viewing without Xcode
/// Access via Settings > Debug Logs
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    @Published private(set) var logs: [LogEntry] = []
    private let maxLogs = 500
    private let queue = DispatchQueue(label: "com.festivair.logger")

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let category: String
        let message: String
        let level: Level

        enum Level: String {
            case info = "ℹ️"
            case success = "✅"
            case warning = "⚠️"
            case error = "❌"
        }

        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }

    private init() {}

    func log(_ message: String, category: String, level: LogEntry.Level = .info) {
        let entry = LogEntry(timestamp: Date(), category: category, message: message, level: level)

        queue.async {
            DispatchQueue.main.async {
                self.logs.append(entry)
                if self.logs.count > self.maxLogs {
                    self.logs.removeFirst(self.logs.count - self.maxLogs)
                }
            }
        }

        // Also print to console for Xcode debugging
        print("[\(category)] \(level.rawValue) \(message)")
    }

    func clear() {
        DispatchQueue.main.async {
            self.logs.removeAll()
        }
    }

    func export() -> String {
        logs.map { "[\($0.formattedTime)] [\($0.category)] \($0.level.rawValue) \($0.message)" }
            .joined(separator: "\n")
    }
}

// MARK: - Convenience Functions
extension DebugLogger {
    static func info(_ message: String, category: String) {
        shared.log(message, category: category, level: .info)
    }

    static func success(_ message: String, category: String) {
        shared.log(message, category: category, level: .success)
    }

    static func warning(_ message: String, category: String) {
        shared.log(message, category: category, level: .warning)
    }

    static func error(_ message: String, category: String) {
        shared.log(message, category: category, level: .error)
    }
}

// MARK: - Debug Log View
struct DebugLogView: View {
    @ObservedObject private var logger = DebugLogger.shared
    @State private var filterCategory: String?
    @State private var showShareSheet = false
    @State private var autoScroll = true

    private var categories: [String] {
        Array(Set(logger.logs.map { $0.category })).sorted()
    }

    private var filteredLogs: [DebugLogger.LogEntry] {
        if let category = filterCategory {
            return logger.logs.filter { $0.category == category }
        }
        return logger.logs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    DebugFilterChip(title: "All", isSelected: filterCategory == nil) {
                        filterCategory = nil
                    }
                    ForEach(categories, id: \.self) { category in
                        DebugFilterChip(title: category, isSelected: filterCategory == category) {
                            filterCategory = category
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGray6))

            // Logs
            if filteredLogs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary)
                    Text("No logs yet")
                        .font(.headline)
                    Text("Logs will appear here as you use the app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredLogs) { entry in
                                LogEntryRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: logger.logs.count) { _, _ in
                        if autoScroll, let lastLog = filteredLogs.last {
                            withAnimation {
                                proxy.scrollTo(lastLog.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Debug Logs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle("Auto-scroll", isOn: $autoScroll)

                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share Logs", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive) {
                        logger.clear()
                    } label: {
                        Label("Clear Logs", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            DebugShareSheet(items: [logger.export()])
        }
    }
}

private struct DebugFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.purple : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

struct LogEntryRow: View {
    let entry: DebugLogger.LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.level.rawValue)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.formattedTime)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("[\(entry.category)]")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.purple)
                }

                Text(entry.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var backgroundColor: Color {
        switch entry.level {
        case .error: return Color.red.opacity(0.1)
        case .warning: return Color.orange.opacity(0.1)
        case .success: return Color.green.opacity(0.1)
        case .info: return Color(.systemGray6)
        }
    }
}

// MARK: - Debug Share Sheet
private struct DebugShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
