import SwiftUI

struct ChaliceView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 16, weight: .ultraLight))
                .foregroundColor(.secondary)

            if let session = sessionManager.currentSession {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.intention)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)

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
