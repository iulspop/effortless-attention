import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearance: AppearanceManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.system(size: 18, weight: .medium, design: .serif))

            VStack(alignment: .leading, spacing: 10) {
                Text("Appearance")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                Picker("", selection: $appearance.mode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Active Session Display")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                Picker("", selection: $appearance.chaliceDisplay) {
                    ForEach(ChaliceDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
