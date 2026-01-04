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

                // Citation Style Settings
                Section(header: Text("Citation Style").font(.headline)) {
                    // Citation Command Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Citation Command")
                        Picker("", selection: $viewModel.citationStyle) {
                            Text("\\cite{}").tag("cite")
                            Text("\\citep{}").tag("citep")
                            Text("\\citet{}").tag("citet")
                            Text("\\autocite{}").tag("autocite")
                            Text("\\parencite{}").tag("parencite")
                        }
                        .pickerStyle(.segmented)

                        Text(viewModel.citationStyleDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()
                        .padding(.vertical, 4)

                    // Citation Density Slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Citation Density")
                            Spacer()
                            Text(viewModel.densityLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.citationDensity) },
                            set: { viewModel.citationDensity = Int($0) }
                        ), in: 0...100, step: 10)

                        HStack {
                            Text("Minimal")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Comprehensive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(viewModel.densityDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }

                // Citation Search Settings
                Section(header: Text("Paper Search").font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Strictness")
                            Spacer()
                            Text(viewModel.strictnessLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(viewModel.searchStrictness) },
                            set: { viewModel.searchStrictness = Int($0) }
                        ), in: 0...100, step: 10)

                        HStack {
                            Text("Relaxed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Strict")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text(viewModel.strictnessDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
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
        .frame(width: 520, height: 750)
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
    @Published var searchStrictness = 30
    @Published var citationStyle = "cite"
    @Published var citationDensity = 50

    // Citation Style descriptions
    var citationStyleDescription: String {
        switch citationStyle {
        case "cite": return "Standard citation: (Author, Year) or [1]"
        case "citep": return "Parenthetical: (Author, Year) - natbib package"
        case "citet": return "Textual: Author (Year) - natbib package"
        case "autocite": return "Auto-formatted citation - biblatex package"
        case "parencite": return "Parenthetical citation - biblatex package"
        default: return ""
        }
    }

    // Citation Density labels and descriptions
    var densityLabel: String {
        switch citationDensity {
        case 0..<20: return "Minimal"
        case 20..<40: return "Light"
        case 40..<60: return "Balanced"
        case 60..<80: return "Thorough"
        default: return "Comprehensive"
        }
    }

    var densityDescription: String {
        switch citationDensity {
        case 0..<20: return "Only cite essential claims. Best for drafts or when you already have citations."
        case 20..<40: return "Cite key claims and important methods. Skip well-known facts."
        case 40..<60: return "Balanced approach: cite most claims and all model/method names."
        case 60..<80: return "Thorough citations including supporting evidence and comparisons."
        default: return "Comprehensive: cite everything that can be cited, including foundational concepts."
        }
    }

    // Search Strictness labels and descriptions
    var strictnessLabel: String {
        switch searchStrictness {
        case 0..<20: return "Very Relaxed"
        case 20..<40: return "Relaxed"
        case 40..<60: return "Balanced"
        case 60..<80: return "Strict"
        default: return "Very Strict"
        }
    }

    var strictnessDescription: String {
        switch searchStrictness {
        case 0..<20: return "Accepts most papers regardless of venue or age. Good for niche topics."
        case 20..<40: return "Prefers quality papers but includes older or less cited works."
        case 40..<60: return "Balanced between quality and coverage."
        case 60..<80: return "Prioritizes top venues and recent papers. May miss some relevant works."
        default: return "Only top conferences and recent papers. Best for well-researched topics."
        }
    }

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
        searchStrictness = config.searchStrictness
        citationStyle = config.citationStyle
        citationDensity = config.citationDensity
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
            minCitationCount: minCitationCount,
            searchStrictness: searchStrictness,
            citationStyle: citationStyle,
            citationDensity: citationDensity,
            minYear: 0
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
