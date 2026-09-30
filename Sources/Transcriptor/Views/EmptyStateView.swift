import SwiftUI

/// Shows a placeholder icon, title and optional message when no transcript or job is selected.
struct EmptyStateView: View {
    /// SF Symbol name shown above the title.
    let systemImage: String
    /// Headline text.
    let title: String
    /// Secondary text shown below the title; hidden when empty.
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3)
            if !message.isEmpty {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
