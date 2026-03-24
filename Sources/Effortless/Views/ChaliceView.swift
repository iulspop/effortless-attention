import SwiftUI

struct ChaliceView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 16, weight: .ultraLight))
                .foregroundColor(.secondary)

            if let ctx = sessionManager.activeContext {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ctx.label)
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(ctx.intention)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(sessionManager.remainingTimeFormatted)
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
        )
    }
}
