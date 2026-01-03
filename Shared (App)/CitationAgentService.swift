//
//  CitationAgentService.swift
//  CiteAgent
//
//  Main service for processing LaTeX text and adding citations using LLM + paper search
//

import Foundation

@available(macOS 12.0, iOS 15.0, *)
class CitationAgentService {
    private let config: AppConfig
    private let paperSearchService: PaperSearchService
    private var paperCache: [String: [Paper]] = [:]
    private var bibtexCache: [String: String] = [:]

    init(config: AppConfig) {
        self.config = config
        self.paperSearchService = PaperSearchService(apiKey: config.semanticScholarApiKey.isEmpty ? nil : config.semanticScholarApiKey)
    }

    // Main function to process LaTeX text and add citations
    func processText(_ latexText: String, context: String? = nil) async throws -> CitationResponse {
        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Processing LaTeX Text (Provider: \(config.llmProvider))")
        print(String(repeating: "=", count: 60))

        // For now, we'll implement a simplified version that uses Gemini API
        // In a production app, you'd want to implement proper function calling with Gemini/Upstage

        if config.llmProvider == "gemini" {
            return try await processWithGemini(latexText, context: context)
        } else {
            return try await processWithUpstage(latexText, context: context)
        }
    }

    // MARK: - Gemini Integration

    private func processWithGemini(_ text: String, context: String?) async throws -> CitationResponse {
        // In a real implementation, you would use Google's Generative AI SDK for Swift
        // For now, we'll use URLSession to make direct API calls

        let apiKey = config.geminiApiKey
        guard !apiKey.isEmpty else {
            throw AgentError.missingApiKey("Gemini API key not configured")
        }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(config.geminiModel):generateContent?key=\(apiKey)")!

        let systemInstruction = buildSystemInstruction()
        let userPrompt = buildUserPrompt(text: text)

        let requestBody: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": systemInstruction + "\n\n" + userPrompt]]]
            ],
            "generationConfig": [
                "temperature": config.temperature
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("[Agent] Sending request to Gemini API...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentError.apiError("Gemini API request failed")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let firstCandidate = geminiResponse.candidates.first,
              let firstPart = firstCandidate.content.parts.first else {
            throw AgentError.apiError("No response from Gemini")
        }

        let modifiedText = firstPart.text

        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Processing Complete")
        print(String(repeating: "=", count: 60))

        // For now, return empty bibtex entries - in full implementation,
        // this would involve function calling to search papers
        return CitationResponse(modifiedText: modifiedText, bibtexEntries: [], error: nil)
    }

    // MARK: - Upstage Integration

    private func processWithUpstage(_ text: String, context: String?) async throws -> CitationResponse {
        let apiKey = config.upstageApiKey
        guard !apiKey.isEmpty else {
            throw AgentError.missingApiKey("Upstage API key not configured")
        }

        let url = URL(string: "https://api.upstage.ai/v1/chat/completions")!

        let systemMessage = buildSystemInstruction()
        let userMessage = buildUserPrompt(text: text)

        let requestBody: [String: Any] = [
            "model": config.upstageModel,
            "messages": [
                ["role": "system", "content": systemMessage],
                ["role": "user", "content": userMessage]
            ],
            "temperature": config.temperature
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        print("[Agent] Sending request to Upstage API...")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentError.apiError("Upstage API request failed")
        }

        let upstageResponse = try JSONDecoder().decode(UpstageResponse.self, from: data)

        guard let firstChoice = upstageResponse.choices.first else {
            throw AgentError.apiError("No response from Upstage")
        }

        let modifiedText = firstChoice.message.content

        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Processing Complete")
        print(String(repeating: "=", count: 60))

        return CitationResponse(modifiedText: modifiedText, bibtexEntries: [], error: nil)
    }

    // MARK: - Prompt Building

    private func buildSystemInstruction() -> String {
        return """
        You are an academic research assistant specialized in adding citations to LaTeX documents.
        Your task is to:
        1. **THOROUGHLY** identify ALL claims, statements, facts, models, methods, or concepts that need citations
        2. Insert \\cite{key} tags at appropriate positions

        **CRITICAL CITATION REQUIREMENTS**:
        - **DO NOT add citations to \\begin{abstract}...\\end{abstract} sections**
        - Add citations for EVERY factual claim in the main text
        - When mentioning specific models (e.g., 'WavLM', 'BERT', 'GPT'), cite the original paper
        - When mentioning specific methods (e.g., 'PCA', 'orthogonal projection'), cite foundational papers
        - Use multiple citations \\cite{paper1,paper2,paper3} when appropriate
        - Add citations in the MIDDLE of sentences when specific concepts are introduced

        **Citation Style Guidelines**:
        - Use \\cite{} for all citations: Some work has been done~\\cite{author2020}
        - Always use \\cite{} consistently (not \\citep or \\citet)

        **Examples of GOOD citation placement**:
        ✓ "WavLM~\\cite{chen2022wavlm} is a self-supervised model that..."
        ✓ "Recent work on speech synthesis~\\cite{wang2023,li2024,zhang2024} has shown..."

        Do NOT modify the text content itself, ONLY add citation commands.
        Return ONLY the modified text with citations, without explanations.
        """
    }

    private func buildUserPrompt(text: String) -> String {
        return """
        Please add COMPREHENSIVE citations to this LaTeX text.
        Identify EVERY claim, model name, method, dataset, and concept that needs citation.

        LaTeX text to process:

        \(text)
        """
    }

    // MARK: - Paper Search Tools

    func searchPaper(query: String, limit: Int = 5) async throws -> [Paper] {
        let cacheKey = "\(query)_\(limit)"
        if let cached = paperCache[cacheKey] {
            print("[Agent] Using cached results for: \(query)")
            return cached
        }

        let papers = try await paperSearchService.searchPapers(
            query: query,
            limit: limit,
            minCitations: config.minCitationCount
        )

        paperCache[cacheKey] = papers
        return papers
    }

    func getBibtex(for paper: Paper) -> String {
        let key = paper.bibtexKey()
        if let cached = bibtexCache[key] {
            print("[Agent] Using cached BibTeX for: \(key)")
            return cached
        }

        let bibtex = paper.bibtexEntry()
        bibtexCache[key] = bibtex
        return bibtex
    }

    // MARK: - Error Types

    enum AgentError: Error {
        case missingApiKey(String)
        case apiError(String)
    }
}

// MARK: - API Response Models

private struct GeminiResponse: Codable {
    let candidates: [GeminiCandidate]
}

private struct GeminiCandidate: Codable {
    let content: GeminiContent
}

private struct GeminiContent: Codable {
    let parts: [GeminiPart]
}

private struct GeminiPart: Codable {
    let text: String
}

private struct UpstageResponse: Codable {
    let choices: [UpstageChoice]
}

private struct UpstageChoice: Codable {
    let message: UpstageMessage
}

private struct UpstageMessage: Codable {
    let content: String
}
