import SwiftUI

struct SetupView: View {
    @ObservedObject var appState: AppState
    var onSave: () -> Void

    @State private var tokenInput: String = ""
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metra Tracker Setup")
                .font(.headline)

            Text("Enter your Metra GTFS API token. You can get one from metra.com/metra-gtfs-api")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("API Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)

            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Save") {
                    let trimmed = tokenInput.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else {
                        errorText = "Token cannot be empty."
                        return
                    }
                    if KeychainHelper.saveToken(trimmed) {
                        appState.apiToken = trimmed
                        onSave()
                    } else {
                        errorText = "Failed to save to Keychain."
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
