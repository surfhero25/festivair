import SwiftUI

/// Shareable festival summary card (Premium feature)
struct FestivalSummaryView: View {
    @StateObject private var analyticsService = AnalyticsService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var summary: FestivalSummary?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let summary = summary {
                        // Summary Card
                        summaryCard(summary)

                        // Detailed Stats
                        detailedStats(summary)

                        // Daily Breakdown
                        if !analyticsService.dailyStats.isEmpty {
                            dailyBreakdown
                        }

                        // Share Button
                        shareButton
                    } else {
                        ProgressView("Loading stats...")
                    }
                }
                .padding()
            }
            .navigationTitle("Festival Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                summary = analyticsService.generateFestivalSummary()
            }
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ summary: FestivalSummary) -> some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("🎪")
                    .font(.system(size: 60))

                Text(summary.activityLevel)
                    .font(.title)
                    .fontWeight(.bold)

                Text("Your Festival Experience")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Key Stats Grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                statBox(
                    icon: "figure.walk",
                    value: "\(summary.totalSteps.formatted())",
                    label: "Steps"
                )

                statBox(
                    icon: "map",
                    value: summary.formattedDistance,
                    label: "Distance"
                )

                statBox(
                    icon: "music.note.house",
                    value: "\(summary.stagesVisited)",
                    label: "Stages"
                )

                statBox(
                    icon: "clock",
                    value: "\(summary.activeMinutes)",
                    label: "Active Mins"
                )
            }

            // Days Badge
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.purple)
                Text("\(summary.daysAttended) day\(summary.daysAttended == 1 ? "" : "s") of festival fun!")
                    .font(.subheadline)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.2), .pink.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
        )
    }

    private func statBox(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.purple)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Detailed Stats

    private func detailedStats(_ summary: FestivalSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Highlights")
                .font(.headline)

            VStack(spacing: 12) {
                if let peakHour = summary.formattedPeakHour {
                    detailRow(
                        icon: "sun.max.fill",
                        title: "Peak Activity",
                        value: peakHour,
                        color: .orange
                    )
                }

                if let topStage = summary.topStage {
                    detailRow(
                        icon: "star.fill",
                        title: "Top Stage",
                        value: topStage,
                        color: .yellow
                    )
                }

                detailRow(
                    icon: "flame.fill",
                    title: "Calories Burned",
                    value: "~\(Int(Double(summary.totalSteps) * 0.04))",
                    color: .red
                )

                detailRow(
                    icon: "bolt.fill",
                    title: "Energy Level",
                    value: energyLevel(for: summary),
                    color: .green
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func detailRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }

    private func energyLevel(for summary: FestivalSummary) -> String {
        let score = summary.totalSteps + (summary.activeMinutes * 100) + (summary.stagesVisited * 500)
        if score > 25000 { return "🔥 Maximum" }
        if score > 15000 { return "⚡️ High" }
        if score > 8000 { return "✨ Good" }
        return "🌴 Chill"
    }

    // MARK: - Daily Breakdown

    private var dailyBreakdown: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Breakdown")
                .font(.headline)

            ForEach(analyticsService.dailyStats) { day in
                HStack {
                    Text(day.date, format: .dateTime.weekday(.wide))
                        .font(.subheadline)

                    Spacer()

                    HStack(spacing: 16) {
                        Label("\(day.steps.formatted())", systemImage: "figure.walk")
                        Label(String(format: "%.1f km", day.distanceKm), systemImage: "map")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                if day.id != analyticsService.dailyStats.last?.id {
                    Divider()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Share Button

    private var shareButton: some View {
        Button {
            showShareSheet = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Share My Festival Stats")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .sheet(isPresented: $showShareSheet) {
            if let summary = summary {
                ShareSheet(items: [createShareText(summary)])
            }
        }
    }

    private func createShareText(_ summary: FestivalSummary) -> String {
        """
        🎪 My Festival Stats from FestivAir!

        🚶 \(summary.totalSteps.formatted()) steps
        📍 \(summary.formattedDistance) walked
        🎵 \(summary.stagesVisited) stages visited
        ⏱ \(summary.activeMinutes) active minutes

        Activity Level: \(summary.activityLevel)

        #FestivAir #FestivalLife
        """
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    FestivalSummaryView()
}
