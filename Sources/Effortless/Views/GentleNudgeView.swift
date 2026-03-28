import SwiftUI

/// Small overlay near the chalice that nudges the user back to their intention.
/// Dismissable with "Not distracted" button which feeds back to the LLM allowlist.
struct GentleNudgeView: View {
    let appName: String
    let intention: String
    let onDismiss: () -> Void  // "not distracted" — feeds back to allowlist

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You're on **\(appName)**")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .foregroundColor(.primary)

            Text("Back to: \(intention)")
                .font(.system(size: 12, weight: .light, design: .serif))
                .foregroundColor(.secondary)

            Button(action: onDismiss) {
                Text("Not distracted")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
