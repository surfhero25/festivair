import Foundation
import Sentry

/// Routes call sites to Sentry breadcrumbs (and console in DEBUG).
/// Crashes and captured errors automatically attach the most recent breadcrumbs.
enum DebugLogger {
    static func info(_ message: String, category: String) {
        emit(message, category: category, level: .info, marker: "ℹ️")
    }

    static func success(_ message: String, category: String) {
        emit(message, category: category, level: .info, marker: "✅")
    }

    static func warning(_ message: String, category: String) {
        emit(message, category: category, level: .warning, marker: "⚠️")
    }

    static func error(_ message: String, category: String) {
        emit(message, category: category, level: .error, marker: "❌")
    }

    private static func emit(_ message: String, category: String, level: SentryLevel, marker: String) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)

        #if DEBUG
        print("[\(category)] \(marker) \(message)")
        #endif
    }
}
