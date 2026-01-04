//
//  CitationAgentService.swift
//  CiteAgent
//
//  Main agent service for adding citations to academic text
//

import Foundation

class CitationAgentService {
    private let config: AppConfig
    private let paperSearchService: PaperSearchService

    enum AgentError: Error {
        case missingApiKey(String)
        case apiError(String)
    }

    init(config: AppConfig) {
        self.config = config
        self.paperSearchService = PaperSearchService()
    }

    // Main entry point for processing text
    func processText(_ text: String, context: String? = nil) async throws -> CitationResponse {
        switch config.llmProvider {
        case "gemini":
            return try await processWithGemini(text, context: context)
        case "upstage":
            return try await processWithUpstage(text, context: context)
        default:
            return try await processWithGemini(text, context: context)
        }
    }

    // Public wrapper for paper search (used by SafariWebExtensionHandler)
    func searchPaper(query: String, limit: Int = 5) async throws -> [Paper] {
        return try await paperSearchService.searchPapers(query: query, limit: limit, minCitations: 0)
    }

    // MARK: - Gemini Integration

    private func processWithGemini(_ text: String, context: String?) async throws -> CitationResponse {
        let apiKey = config.geminiApiKey
        guard !apiKey.isEmpty else {
            throw AgentError.missingApiKey("Gemini API key not configured")
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(config.geminiModel):generateContent?key=\(apiKey)"
        let url = URL(string: urlString)!

        let systemInstruction = buildSystemInstruction()
        let userPrompt = buildUserPrompt(text: text)

        let requestBody: [String: Any] = [
            "system_instruction": ["parts": [["text": systemInstruction]]],
            "contents": [["parts": [["text": userPrompt]]]],
            "generationConfig": ["temperature": config.temperature]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentError.apiError("Gemini API request failed")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let firstCandidate = geminiResponse.candidates.first,
              let firstPart = firstCandidate.content.parts.first else {
            throw AgentError.apiError("No response from Gemini")
        }

        var modifiedText = firstPart.text

        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Extracting citation keys and searching papers")
        print(String(repeating: "=", count: 60))

        let citationKeys = extractCitationKeys(from: modifiedText)
        print("[Agent] Found \(citationKeys.count) citation keys: \(citationKeys)")

        var bibtexEntries: [String] = []
        var keyMapping: [String: String] = [:]
        var keysToRemove: [String] = []

        for key in citationKeys {
            do {
                let paper = try await searchPaperWithRetry(key: key)

                if let paper = paper {
                    let actualKey = paper.bibtexKey()
                    let bibtex = paper.bibtexEntry()

                    if !bibtexEntries.contains(where: { $0.contains("{\(actualKey),") }) {
                        bibtexEntries.append(bibtex)
                    }
                    keyMapping[key] = actualKey
                    print("[Agent] ✅ Found: \(paper.title)")
                    print("[Agent]    Key mapping: \(key) -> \(actualKey)")
                } else {
                    print("[Agent] ❌ No paper found for: \(key) - will remove citation")
                    keysToRemove.append(key)
                }
            } catch {
                print("[Agent] ❌ Error searching for \(key): \(error) - will remove citation")
                keysToRemove.append(key)
            }
        }

        modifiedText = replaceCitationKeys(in: modifiedText, using: keyMapping)

        for key in keysToRemove {
            modifiedText = removeCitation(key: key, from: modifiedText)
        }

        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Processing Complete")
        print("  - \(bibtexEntries.count) BibTeX entries generated")
        print("  - Key mappings: \(keyMapping)")
        if !keysToRemove.isEmpty {
            print("  - Removed citations (not found): \(keysToRemove)")
        }
        print(String(repeating: "=", count: 60))

        return CitationResponse(modifiedText: modifiedText, bibtexEntries: bibtexEntries, error: nil)
    }

    // Search for a paper with multiple retry strategies
    private func searchPaperWithRetry(key: String) async throws -> Paper? {
        let queries = generateSearchQueries(from: key)

        // Use strictness-based settings
        let minCitations = config.effectiveMinCitations
        let matchThreshold = config.effectiveMatchThreshold

        print("[Agent] Search settings: strictness=\(config.searchStrictness), minCitations=\(minCitations), matchThreshold=\(matchThreshold)")

        for query in queries {
            print("[Agent] Trying search: '\(query)'")
            let papers = try await paperSearchService.searchPapers(
                query: query,
                limit: config.maxPapersPerSearch,
                minCitations: minCitations,
                minYear: config.effectiveMinYear
            )

            if let bestMatch = findBestMatch(papers: papers, key: key, threshold: matchThreshold) {
                return bestMatch
            }
        }

        return nil
    }

    private func generateSearchQueries(from key: String) -> [String] {
        var queries: [String] = []

        queries.append(truncateToThreeWords(key))

        let withHyphens = insertHyphens(key)
        if withHyphens != key {
            queries.append(truncateToThreeWords(withHyphens))
        }

        let standard = createSearchQuery(from: key)
        let truncatedStandard = truncateToThreeWords(standard)
        if !queries.contains(truncatedStandard) {
            queries.append(truncatedStandard)
        }

        let upper = key.uppercased()
        if !queries.contains(upper) {
            queries.append(truncateToThreeWords(upper))
        }

        return Array(Set(queries)).filter { !$0.isEmpty }
    }

    private func truncateToThreeWords(_ query: String) -> String {
        let words = query.split(separator: " ").map(String.init)
        return words.prefix(3).joined(separator: " ")
    }

    private func insertHyphens(_ key: String) -> String {
        var result = key

        let patterns = [
            (#"([a-z])(\d)"#, "$1-$2"),
            (#"(\d)([a-z])"#, "$1-$2"),
        ]

        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }

        return result.uppercased()
    }

    private func findBestMatch(papers: [Paper], key: String, threshold: Int = 0) -> Paper? {
        guard !papers.isEmpty else { return nil }

        // If only one paper found, just return it (relaxed mode)
        if papers.count == 1 && threshold < 30 {
            return papers.first
        }

        let keyLower = key.lowercased()
        let keyClean = keyLower.replacingOccurrences(of: "-", with: "")
                               .replacingOccurrences(of: "_", with: "")
                               .replacingOccurrences(of: " ", with: "")
                               .replacingOccurrences(of: "0", with: "")
                               .replacingOccurrences(of: "1", with: "")
                               .replacingOccurrences(of: "2", with: "")

        var bestPaper: Paper? = nil
        var bestScore = 0

        for paper in papers {
            var score = 0
            let titleLower = paper.title.lowercased()
            let titleClean = titleLower.replacingOccurrences(of: "-", with: "")
                                       .replacingOccurrences(of: "_", with: "")
                                       .replacingOccurrences(of: " ", with: "")

            if titleClean.contains(keyClean) {
                score += 100
            }

            let keyWords = keyLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }
            for word in keyWords {
                if titleLower.contains(word) {
                    score += 30
                }
            }

            score += min(paper.citationCount / 5, 30)

            if score > bestScore {
                bestScore = score
                bestPaper = paper
            }
        }

        // Apply threshold check: require minimum score based on strictness
        if bestScore < threshold {
            print("[Agent] Best match score (\(bestScore)) below threshold (\(threshold))")
            // In relaxed mode (threshold < 30), still return first paper
            if threshold < 30 {
                return bestPaper ?? papers.first
            }
            return nil
        }

        // Return best match, or first paper if no good match in relaxed mode
        return bestPaper ?? (threshold < 30 ? papers.first : nil)
    }

    private func removeCitation(key: String, from text: String) -> String {
        var result = text
        let escapedKey = NSRegularExpression.escapedPattern(for: key)

        // Remove ~\cite{key} or \cite{key} for all citation command types
        let citeCmds = ["cite", "citep", "citet", "autocite", "parencite"]
        for cmd in citeCmds {
            let patterns = [
                "~\\\\\(cmd)\\{\(escapedKey)\\}",
                "\\\\\(cmd)\\{\(escapedKey)\\}"
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "")
                }
            }
        }

        result = result.replacingOccurrences(of: "{\(key), ", with: "{")
        result = result.replacingOccurrences(of: "{\(key),", with: "{")
        result = result.replacingOccurrences(of: ", \(key), ", with: ", ")
        result = result.replacingOccurrences(of: ",\(key),", with: ",")
        result = result.replacingOccurrences(of: ", \(key)}", with: "}")
        result = result.replacingOccurrences(of: ",\(key)}", with: "}")

        return result
    }

    private func replaceCitationKeys(in text: String, using mapping: [String: String]) -> String {
        var result = text

        // Use regex to find all citation patterns and replace keys inside
        // Captures: (1) the citation command, (2) the keys
        let pattern = #"\\(cite|citep|citet|autocite|parencite)\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range).reversed()

        for match in matches {
            guard let fullRange = Range(match.range, in: result),
                  let cmdRange = Range(match.range(at: 1), in: result),
                  let keysRange = Range(match.range(at: 2), in: result) else {
                continue
            }

            let citeCmd = String(result[cmdRange])
            let keysString = String(result[keysRange])
            let keys = keysString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

            let newKeys = keys.map { key -> String in
                return mapping[key] ?? key
            }

            let newKeysString = newKeys.joined(separator: ", ")
            let newCite = "\\\(citeCmd){\(newKeysString)}"

            result.replaceSubrange(fullRange, with: newCite)
        }

        return result
    }

    // MARK: - Citation Key Extraction

    private func extractCitationKeys(from text: String) -> [String] {
        var keys: Set<String> = []

        // Match multiple citation commands: \cite, \citep, \citet, \autocite, \parencite
        let pattern = #"\\(?:cite|citep|citet|autocite|parencite)\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: text) {
                let keyString = String(text[keyRange])
                let individualKeys = keyString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for key in individualKeys {
                    keys.insert(key)
                }
            }
        }

        return Array(keys)
    }

    private func createSearchQuery(from citationKey: String) -> String {
        var query = citationKey

        let yearPattern = #"(19|20)\d{2}"#
        var year = ""
        if let yearRegex = try? NSRegularExpression(pattern: yearPattern, options: []),
           let match = yearRegex.firstMatch(in: query, options: [], range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range, in: query) {
            year = String(query[range])
            query = query.replacingOccurrences(of: year, with: " ")
        }

        var result = ""
        for char in query {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }

        result = result.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        if !year.isEmpty {
            result += " " + year
        }

        return result.trimmingCharacters(in: .whitespaces)
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AgentError.apiError("Upstage API request failed")
        }

        let upstageResponse = try JSONDecoder().decode(UpstageResponse.self, from: data)

        guard let firstChoice = upstageResponse.choices.first else {
            throw AgentError.apiError("No response from Upstage")
        }

        var modifiedText = firstChoice.message.content

        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Extracting citation keys and searching papers")
        print(String(repeating: "=", count: 60))

        let citationKeys = extractCitationKeys(from: modifiedText)
        print("[Agent] Found \(citationKeys.count) citation keys: \(citationKeys)")

        var bibtexEntries: [String] = []
        var keyMapping: [String: String] = [:]
        var keysToRemove: [String] = []

        for key in citationKeys {
            do {
                let paper = try await searchPaperWithRetry(key: key)

                if let paper = paper {
                    let actualKey = paper.bibtexKey()
                    let bibtex = paper.bibtexEntry()

                    if !bibtexEntries.contains(where: { $0.contains("{\(actualKey),") }) {
                        bibtexEntries.append(bibtex)
                    }
                    keyMapping[key] = actualKey
                    print("[Agent] ✅ Found: \(paper.title)")
                    print("[Agent]    Key mapping: \(key) -> \(actualKey)")
                } else {
                    print("[Agent] ❌ No paper found for: \(key) - will remove citation")
                    keysToRemove.append(key)
                }
            } catch {
                print("[Agent] ❌ Error searching for \(key): \(error) - will remove citation")
                keysToRemove.append(key)
            }
        }

        modifiedText = replaceCitationKeys(in: modifiedText, using: keyMapping)

        for key in keysToRemove {
            modifiedText = removeCitation(key: key, from: modifiedText)
        }

        print("\n" + String(repeating: "=", count: 60))
        print("CITATION AGENT: Processing Complete")
        print("  - \(bibtexEntries.count) BibTeX entries generated")
        print("  - Key mappings: \(keyMapping)")
        if !keysToRemove.isEmpty {
            print("  - Removed citations (not found): \(keysToRemove)")
        }
        print(String(repeating: "=", count: 60))

        return CitationResponse(modifiedText: modifiedText, bibtexEntries: bibtexEntries, error: nil)
    }

    // MARK: - Prompt Building

    private func buildSystemInstruction() -> String {
        let citeCmd = config.citationStyle
        let densityInstruction = getDensityInstruction()

        return """
        You are an academic research assistant specialized in adding citations to LaTeX documents.
        Your task is to:
        1. Identify claims, statements, facts, models, methods, or concepts that need citations
        2. Insert \\\(citeCmd){key} tags at appropriate positions

        **CRITICAL CITATION REQUIREMENTS**:
        - **DO NOT add citations to \\begin{abstract}...\\end{abstract} sections**
        \(densityInstruction)
        - When mentioning specific models (e.g., 'WavLM', 'BERT', 'GPT'), cite the original paper
        - When mentioning specific methods or algorithms, cite foundational papers
        - Use multiple citations \\\(citeCmd){paper1,paper2,paper3} when appropriate
        - Add citations in the MIDDLE of sentences when specific concepts are introduced

        **Citation Style Guidelines**:
        - Use \\\(citeCmd){} for ALL citations: Some work has been done~\\\(citeCmd){author2020}
        - Always use \\\(citeCmd){} consistently (do NOT use other citation commands)

        **Examples of GOOD citation placement**:
        ✓ "WavLM~\\\(citeCmd){chen2022wavlm} is a self-supervised model that..."
        ✓ "Recent work on speech synthesis~\\\(citeCmd){wang2023,li2024,zhang2024} has shown..."

        Do NOT modify the text content itself, ONLY add citation commands.
        Return ONLY the modified text with citations, without explanations.
        """
    }

    private func getDensityInstruction() -> String {
        switch config.citationDensity {
        case 0..<20:
            return """
            - Add citations ONLY for essential claims that absolutely require references
            - Skip well-known facts and common knowledge
            - Focus on the most important 2-3 citations per paragraph
            """
        case 20..<40:
            return """
            - Add citations for key claims and important methods
            - Skip well-known facts (e.g., "neural networks can learn representations")
            - Cite specific model names and novel concepts
            """
        case 40..<60:
            return """
            - Add citations for most factual claims
            - Cite all model names, method names, and datasets
            - Include citations for comparisons and related work
            """
        case 60..<80:
            return """
            - Add thorough citations including supporting evidence
            - Cite model names, methods, datasets, and comparisons
            - Include citations for background concepts and motivation
            """
        default:
            return """
            - Add COMPREHENSIVE citations for EVERY factual claim
            - Cite ALL model names, methods, datasets, metrics, and concepts
            - Include citations for foundational concepts and well-known methods
            - Multiple citations for important claims when appropriate
            """
        }
    }

    private func buildUserPrompt(text: String) -> String {
        let densityPrompt = getDensityPrompt()

        return """
        Please add citations to this LaTeX text.
        \(densityPrompt)

        LaTeX text to process:

        \(text)
        """
    }

    private func getDensityPrompt() -> String {
        switch config.citationDensity {
        case 0..<20:
            return "Add MINIMAL citations - only cite the most essential claims."
        case 20..<40:
            return "Add LIGHT citations - cite key claims and important model/method names."
        case 40..<60:
            return "Add BALANCED citations - cite most claims and all model/method names."
        case 60..<80:
            return "Add THOROUGH citations - cite claims, methods, datasets, and supporting evidence."
        default:
            return "Add COMPREHENSIVE citations - cite everything that can be cited."
        }
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
