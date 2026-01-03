//
//  FloatingNavigatorView.swift
//  CiteAgent (macOS)
//
//  Floating navigator UI - a small window that stays on top
//

import SwiftUI
import SafariServices

struct FloatingNavigatorView: View {
    @StateObject private var viewModel = NavigatorViewModel()

    var body: some View {
        VStack(spacing: 12) {
            // Status indicator
            HStack {
                Circle()
                    .fill(viewModel.isProcessing ? Color.yellow : Color.green)
                    .frame(width: 8, height: 8)

                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Main action button
            Button(action: {
                viewModel.processCitation()
            }) {
                HStack {
                    if viewModel.isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                    }

                    Text(viewModel.isProcessing ? "Processing..." : "Add Citations")
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isProcessing)

            Divider()

            // Secondary actions
            HStack(spacing: 8) {
                Button(action: {
                    viewModel.showSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Spacer()

                Button(action: {
                    viewModel.openSafariPreferences()
                }) {
                    Image(systemName: "safari")
                        .font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("Safari Extension Settings")
            }
        }
        .padding(12)
        .frame(width: 220)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $viewModel.showingSettings) {
            SettingsView()
        }
        .alert("Error", isPresented: $viewModel.showingError, presenting: viewModel.errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { errorMessage in
            Text(errorMessage)
        }
    }
}

// MARK: - View Model

class NavigatorViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var statusText = "Ready"
    @Published var showingSettings = false
    @Published var showingError = false
    @Published var errorMessage: String?

    private let extensionBundleIdentifier = "kyudan.CiteAgent.Extension"

    func processCitation() {
        isProcessing = true
        statusText = "Processing..."

        Task {
            do {
                // Get active tab and send message to content script
                // Note: In a real implementation, you would use SFSafariApplication APIs
                // to communicate with the content script

                // For now, we'll simulate processing
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                await MainActor.run {
                    isProcessing = false
                    statusText = "Ready"
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    statusText = "Error"
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    func showSettings() {
        showingSettings = true
    }

    func openSafariPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: extensionBundleIdentifier) { error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to open Safari preferences: \(error.localizedDescription)"
                    self.showingError = true
                }
            }
        }
    }
}

// MARK: - Preview

struct FloatingNavigatorView_Previews: PreviewProvider {
    static var previews: some View {
        FloatingNavigatorView()
    }
}
