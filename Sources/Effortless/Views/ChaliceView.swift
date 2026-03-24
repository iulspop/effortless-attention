import SwiftUI

struct ChaliceView: View {
    @ObservedObject var sessionManager: SessionManager

    var body: some View {
        HStack(spacing: 14) {
            // Chalice icon
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 16, weight: .ultraLight))
                .foregroundColor(Color(nsColor: NSColor(white: 0.5, alpha: 1.0)))

            if let session = sessionManager.currentSession {
                VStack(alignment: .leading, spacing: 3) {
                    // Intention
                    Text(session.intention)
                        .font(.system(size: 13, weight: .regular, design: .serif))
                        .foregroundColor(Color(nsColor: NSColor(white: 0.2, alpha: 1.0)))
                        .lineLimit(1)

                    // Timer
                    Text(sessionManager.remainingTimeFormatted)
                        .font(.system(size: 12, weight: .light, design: .monospaced))
                        .foregroundColor(Color(nsColor: NSColor(white: 0.45, alpha: 1.0)))
                }
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor(white: 0.97, alpha: 0.95)))
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
        )
    }
}
