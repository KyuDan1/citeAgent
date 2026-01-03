//
//  SettingsView.swift
//  CiteAgent (macOS)
//
//  Settings UI for API keys and configuration
//

import SwiftUI
import Combine

@available(macOS 12.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("CiteAgent Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                // LLM Provider Selection
                Section(header: Text("LLM Provider").font(.headline)) {
                    Picker("Provider", selection: $viewModel.llmProvider) {
                        Text("Gemini").tag("gemini")
                        Text("Upstage").tag("upstage")
                    }
                    .pickerStyle(.segmented)
                }

                // Gemini Settings
                if viewModel.llmProvider == "gemini" {
                    Section(header: Text("Gemini Configuration").font(.headline)) {
                        SecureField("API Key", text: $viewModel.geminiApiKey)
                            .textFieldStyle(.roundedBorder)

                        TextField("Model", text: $viewModel.geminiModel)
                            .textFieldStyle(.roundedBorder)

                        Link("Get API Key →", destination: URL(string: "https://aistudio.google.com/apikey")!)
                            .font(.caption)
                    }
                }

                // Upstage Settings
                if viewModel.llmProvider == "upstage" {
                    Section(header: Text("Upstage Configuration").font(.headline)) {
                        SecureField("API Key", text: $viewModel.upstageApiKey)
                            .textFieldStyle(.roundedBorder)

                        TextField("Model", text: $viewModel.upstageModel)
                            .textFieldStyle(.roundedBorder)

                        Link("Get API Key →", destination: URL(string: "https://console.upstage.ai/")!)
                            .font(.caption)
                    }
                }

                // Semantic Scholar Settings
                Section(header: Text("Paper Search (Semantic Scholar)").font(.headline)) {
                    SecureField("API Key (Optional)", text: $viewModel.semanticScholarApiKey)
                        .textFieldStyle(.roundedBorder)

                    Text("API key is optional but recommended for higher rate limits")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Link("Get API Key →", destination: URL(string: "https://www.semanticscholar.org/product/api")!)
                        .font(.caption)
                }

                // Advanced Settings
                Section(header: Text("Advanced").font(.headline)) {
                    HStack {
                        Text("Temperature")
                        Slider(value: $viewModel.temperature, in: 0...1, step: 0.1)
                        Text(String(format: "%.1f", viewModel.temperature))
                            .frame(width: 30)
                    }

                    HStack {
                        Text("Max Papers per Search")
                        Spacer()
                        TextField("", value: $viewModel.maxPapersPerSearch, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Min Citation Count")
                        Spacer()
                        TextField("", value: $viewModel.minCitationCount, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }
                }
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            viewModel.loadSettings()
        }
    }
}

// MARK: - View Model

@available(macOS 12.0, *)
class SettingsViewModel: ObservableObject {
    @Published var llmProvider = "gemini"
    @Published var geminiApiKey = ""
    @Published var geminiModel = "gemini-2.0-flash-exp"
    @Published var upstageApiKey = ""
    @Published var upstageModel = "solar-pro"
    @Published var semanticScholarApiKey = ""
    @Published var temperature = 0.3
    @Published var maxPapersPerSearch = 5
    @Published var minCitationCount = 10

    func loadSettings() {
        let config = AppConfig.load()
        llmProvider = config.llmProvider
        geminiApiKey = config.geminiApiKey
        geminiModel = config.geminiModel
        upstageApiKey = config.upstageApiKey
        upstageModel = config.upstageModel
        semanticScholarApiKey = config.semanticScholarApiKey
        temperature = config.temperature
        maxPapersPerSearch = config.maxPapersPerSearch
        minCitationCount = config.minCitationCount
    }

    func saveSettings() {
        let config = AppConfig(
            geminiApiKey: geminiApiKey,
            upstageApiKey: upstageApiKey,
            semanticScholarApiKey: semanticScholarApiKey,
            llmProvider: llmProvider,
            geminiModel: geminiModel,
            upstageModel: upstageModel,
            temperature: temperature,
            maxPapersPerSearch: maxPapersPerSearch,
            minCitationCount: minCitationCount
        )
        config.save()
        print("[Settings] Configuration saved")
    }
}

// MARK: - Preview

@available(macOS 12.0, *)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
