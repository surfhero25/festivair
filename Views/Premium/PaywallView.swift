import SwiftUI
import StoreKit

/// Paywall view for subscription purchases
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @State private var selectedTier: PremiumTier = .festivalPass
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Tier Selector
                    tierSelector

                    // Feature Comparison
                    featureComparison

                    // Pricing Cards
                    pricingSection

                    // Purchase Button
                    purchaseButton

                    // Restore Purchases
                    restoreButton

                    // Terms
                    termsSection
                }
                .padding()
            }
            .navigationTitle("Go Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .overlay {
                if isPurchasing {
                    ProgressView("Processing...")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .loadingTimeout(isLoading: $isPurchasing, timeout: 60) {
                errorMessage = "Purchase request timed out. Please try again."
                showError = true
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text("Unlock Premium Features")
                .font(.title2)
                .fontWeight(.bold)

            Text("Get more from your festival experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top)
    }

    // MARK: - Tier Selector

    private var tierSelector: some View {
        HStack(spacing: 0) {
            tierButton(tier: .festivalPass, label: "Festival", icon: "ticket.fill")
            tierButton(tier: .crewPass, label: "Crew", icon: "person.3.fill")
            tierButton(tier: .seasonPass, label: "Season", icon: "crown.fill")
        }
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tierButton(tier: PremiumTier, label: String, icon: String) -> some View {
        Button {
            withAnimation {
                selectedTier = tier
            }
        } label: {
            HStack {
                Image(systemName: icon)
                Text(label)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedTier == tier ? Color.purple : Color.clear)
            .foregroundStyle(selectedTier == tier ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature Comparison

    private var featureComparison: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What's Included")
                .font(.headline)

            VStack(spacing: 12) {
                featureRow(
                    icon: "person.3.fill",
                    title: "Squad Size",
                    values: [.festivalPass: "8 members", .crewPass: "20 members", .seasonPass: "20 members"]
                )

                featureRow(
                    icon: "megaphone.fill",
                    title: "Announcements",
                    values: [.festivalPass: "Included", .crewPass: "Included", .seasonPass: "Included"]
                )

                featureRow(
                    icon: "map.fill",
                    title: "Offline Maps",
                    values: [.festivalPass: "Included", .crewPass: "Included", .seasonPass: "Included"]
                )

                featureRow(
                    icon: "paintbrush.fill",
                    title: "Custom Themes",
                    values: [.crewPass: "Included", .seasonPass: "Included"]
                )

                featureRow(
                    icon: "mappin.and.ellipse",
                    title: "After Party Pins",
                    values: [.crewPass: "Included", .seasonPass: "Included"]
                )

                featureRow(
                    icon: "clock.arrow.circlepath",
                    title: "Festival History",
                    values: [.seasonPass: "Included"]
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func featureRow(icon: String, title: String, values: [PremiumTier: String]) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.purple)

            Text(title)
                .font(.subheadline)

            Spacer()

            if let value = values[selectedTier] {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(Capsule())
            } else {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 12) {
            Text("Pricing")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Price Card
            if let product = currentProduct {
                priceCard(product: product)
            } else {
                // Fallback when StoreKit products haven't loaded
                VStack(spacing: 4) {
                    Text(selectedTier.priceText)
                        .font(.system(size: 36, weight: .bold))
                    Text(selectedTier == .seasonPass ? "/year" : "/event")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple, lineWidth: 2)
                )
            }
        }
    }

    private var currentProduct: Product? {
        let productID: SubscriptionManager.ProductID
        switch selectedTier {
        case .festivalPass: productID = .festivalPass
        case .crewPass: productID = .crewPass
        case .seasonPass: productID = .seasonPass
        default: return nil
        }
        return subscriptionManager.product(for: productID)
    }

    private func priceCard(product: Product) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(product.displayPrice)
                    .font(.system(size: 36, weight: .bold))

                Text(selectedTier == .seasonPass ? "/year" : "/event")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if selectedTier == .seasonPass {
                Text("Best value for festival regulars")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.purple.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.purple, lineWidth: 2)
        )
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            Task {
                await purchase()
            }
        } label: {
            HStack {
                Image(systemName: selectedTier == .seasonPass ? "crown.fill" : "ticket.fill")
                Text(selectedTier == .seasonPass ? "Subscribe to Season Pass" : "Buy \(selectedTier.displayName)")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.purple)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(currentProduct == nil || isPurchasing)
    }

    private func purchase() async {
        guard let product = currentProduct else { return }

        isPurchasing = true
        do {
            if let _ = try await subscriptionManager.purchase(product) {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }

    // MARK: - Restore Button

    private var restoreButton: some View {
        Button {
            Task {
                await subscriptionManager.restorePurchases()
                if subscriptionManager.currentTier != .free {
                    dismiss()
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(.purple)
        }
    }

    // MARK: - Terms

    private var termsSection: some View {
        VStack(spacing: 8) {
            if selectedTier == .seasonPass {
                Text("Subscription auto-renews unless cancelled at least 24 hours before the end of the current period.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("One-time purchase for a single event. No recurring charges.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                if let termsURL = URL(string: "https://festivair.app/terms") {
                    Link("Terms of Service", destination: termsURL)
                }
                if let privacyURL = URL(string: "https://festivair.app/privacy") {
                    Link("Privacy Policy", destination: privacyURL)
                }
            }
            .font(.caption2)
        }
        .padding(.top)
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
}
