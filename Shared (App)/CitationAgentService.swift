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
        print("[Agent] === PROCESS WITH GEMINI ===")
        print("[Agent] Text length: \(text.count) characters")
        print("[Agent] Model: \(config.geminiModel)")

        // In a real implementation, you would use Google's Generative AI SDK for Swift
        // For now, we'll use URLSession to make direct API calls

        let apiKey = config.geminiApiKey
        print("[Agent] API key length: \(apiKey.count) characters")

        guard !apiKey.isEmpty else {
            print("[Agent] ERROR: API key is empty!")
            throw AgentError.missingApiKey("Gemini API key not configured")
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(config.geminiModel):generateContent?key=\(apiKey)"
        print("[Agent] API URL: \(urlString.replacingOccurrences(of: apiKey, with: "***HIDDEN***"))")

        guard let url = URL(string: urlString) else {
            throw AgentError.apiError("Invalid URL for model: \(config.geminiModel)")
        }

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

        let data: Data
        let httpResponse: HTTPURLResponse

        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            data = responseData

            guard let http = response as? HTTPURLResponse else {
                throw AgentError.apiError("Invalid response from server")
            }
            httpResponse = http

            print("[Agent] HTTP Status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                let errorBody = String(data: data, encoding: .utf8) ?? "No error details"
                print("[Agent] Error response: \(errorBody)")
                throw AgentError.apiError("Gemini API request failed (status \(httpResponse.statusCode)): \(errorBody)")
            }
        } catch let error as URLError {
            print("[Agent] URLError: \(error.localizedDescription) (code: \(error.code.rawValue))")
            throw AgentError.apiError("Network error: \(error.localizedDescription). Please check your internet connection and API key.")
        } catch {
            print("[Agent] Unexpected error: \(error)")
            throw error
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

        // Extract citation keys from the modified text
        let citationKeys = extractCitationKeys(from: modifiedText)
        print("[Agent] Found \(citationKeys.count) citation keys: \(citationKeys)")

        // Search for papers and generate BibTeX entries
        // Track: original key -> actualKey (only for found papers)
        var bibtexEntries: [String] = []
        var keyMapping: [String: String] = [:] // original -> actual
        var keysToRemove: [String] = [] // Keys for which no paper was found

        for key in citationKeys {
            do {
                // Try multiple search strategies
                let paper = try await searchPaperWithRetry(key: key)

                if let paper = paper {
                    let actualKey = paper.bibtexKey()
                    let bibtex = paper.bibtexEntry()

                    // Check for duplicate keys
                    if !bibtexEntries.contains(where: { $0.contains("{\(actualKey),") }) {
                        bibtexEntries.append(bibtex)
                    }
                    keyMapping[key] = actualKey
                    print("[Agent] ✅ Found: \(paper.title)")
                    print("[Agent]    Key mapping: \(key) -> \(actualKey)")
                } else {
                    // No paper found - mark for removal
                    print("[Agent] ❌ No paper found for: \(key) - will remove citation")
                    keysToRemove.append(key)
                }
            } catch {
                print("[Agent] ❌ Error searching for \(key): \(error) - will remove citation")
                keysToRemove.append(key)
            }
        }

        // Replace citation keys with actual BibTeX keys
        modifiedText = replaceCitationKeys(in: modifiedText, using: keyMapping)

        // Remove citations for papers that weren't found
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
        // Strategy 1: Search with cleaned-up key (e.g., "f5tts" -> "F5-TTS", "wavlm" -> "WavLM")
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

    // Generate multiple search query variations (max 3 words each)
    private func generateSearchQueries(from key: String) -> [String] {
        var queries: [String] = []

        // 1. Original key as-is (truncated to 3 words)
        queries.append(truncateToThreeWords(key))

        // 2. With hyphens for common patterns (f5tts -> F5-TTS)
        let withHyphens = insertHyphens(key)
        if withHyphens != key {
            queries.append(truncateToThreeWords(withHyphens))
        }

        // 3. Standard conversion (split by capitals, year extraction)
        let standard = createSearchQuery(from: key)
        let truncatedStandard = truncateToThreeWords(standard)
        if !queries.contains(truncatedStandard) {
            queries.append(truncatedStandard)
        }

        // 4. Uppercase version
        let upper = key.uppercased()
        if !queries.contains(upper) {
            queries.append(truncateToThreeWords(upper))
        }

        // Remove duplicates and empty queries
        return Array(Set(queries)).filter { !$0.isEmpty }
    }

    // Truncate query to maximum 3 words
    private func truncateToThreeWords(_ query: String) -> String {
        let words = query.split(separator: " ").map(String.init)
        return words.prefix(3).joined(separator: " ")
    }

    // Insert hyphens for common naming patterns
    private func insertHyphens(_ key: String) -> String {
        var result = key

        // Common patterns: f5tts -> F5-TTS, e2tts -> E2-TTS
        let patterns = [
            (#"([a-z])(\d)"#, "$1-$2"),  // letter followed by digit
            (#"(\d)([a-z])"#, "$1-$2"),  // digit followed by letter
        ]

        for (pattern, replacement) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
            }
        }

        return result.uppercased()
    }

    // Find the best matching paper from search results
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

            // Check if key appears in title
            if titleClean.contains(keyClean) {
                score += 100
            }

            // Check individual words (relaxed: 2+ chars)
            let keyWords = keyLower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 2 }
            for word in keyWords {
                if titleLower.contains(word) {
                    score += 30
                }
            }

            // Prefer papers with more citations
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

    // Remove a citation from text
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

        // Also handle multi-citation cases: \cite{key1, badkey, key2} -> \cite{key1, key2}
        // Remove from beginning: {badkey, -> {
        result = result.replacingOccurrences(of: "{\(key), ", with: "{")
        result = result.replacingOccurrences(of: "{\(key),", with: "{")
        // Remove from middle: , badkey, -> ,
        result = result.replacingOccurrences(of: ", \(key), ", with: ", ")
        result = result.replacingOccurrences(of: ",\(key),", with: ",")
        // Remove from end: , badkey} -> }
        result = result.replacingOccurrences(of: ", \(key)}", with: "}")
        result = result.replacingOccurrences(of: ",\(key)}", with: "}")

        return result
    }

    // Replace citation keys in text using the mapping
    private func replaceCitationKeys(in text: String, using mapping: [String: String]) -> String {
        var result = text

        // Use regex to find all citation patterns and replace keys inside
        // Captures: (1) the citation command, (2) the keys
        let pattern = #"\\(cite|citep|citet|autocite|parencite)\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text
        }

        // Find all matches and process in reverse order to preserve indices
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

            // Replace each key with its mapped value
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
                // Split by comma for multiple citations like \cite{paper1,paper2}
                let individualKeys = keyString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                for key in individualKeys {
                    keys.insert(key)
                }
            }
        }

        return Array(keys)
    }

    private func createSearchQuery(from citationKey: String) -> String {
        // Convert citation key to search query
        // e.g., "chen2022wavlm" -> "chen wavlm 2022"
        // e.g., "vaswani2017attention" -> "vaswani attention 2017"

        var query = citationKey

        // Extract year if present (4 digits)
        let yearPattern = #"(19|20)\d{2}"#
        var year = ""
        if let yearRegex = try? NSRegularExpression(pattern: yearPattern, options: []),
           let match = yearRegex.firstMatch(in: query, options: [], range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range, in: query) {
            year = String(query[range])
            query = query.replacingOccurrences(of: year, with: " ")
        }

        // Add spaces before capital letters
        var result = ""
        for char in query {
            if char.isUppercase && !result.isEmpty {
                result += " "
            }
            result += String(char)
        }

        // Clean up and add year
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

        print("[Agent] Sending request to Upstage API...")

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

        // Extract citation keys from the modified text
        let citationKeys = extractCitationKeys(from: modifiedText)
        print("[Agent] Found \(citationKeys.count) citation keys: \(citationKeys)")

        // Search for papers and generate BibTeX entries
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

        // Replace citation keys with actual BibTeX keys
        modifiedText = replaceCitationKeys(in: modifiedText, using: keyMapping)

        // Remove citations for papers that weren't found
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
