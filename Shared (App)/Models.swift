//
//  Models.swift
//  CiteAgent
//
//  Data models for papers, citations, and configuration
//

import Foundation

// MARK: - Paper Model

struct Paper: Codable, Identifiable {
    let paperId: String
    let title: String
    let authors: [String]
    let year: Int?
    let citationCount: Int
    let doi: String?
    let arxivId: String?
    let abstract: String?

    var id: String { paperId }

    enum CodingKeys: String, CodingKey {
        case paperId
        case title
        case authors
        case year
        case citationCount
        case doi
        case arxivId
        case abstract
    }

    // Generate BibTeX key (e.g., "vaswani2017attention")
    func bibtexKey() -> String {
        let firstAuthor = authors.first ?? "unknown"
        let lastName = firstAuthor.components(separatedBy: " ").last?.lowercased() ?? "unknown"
        let cleanLastName = lastName.filter { $0.isLetter }

        let yearStr = String(year ?? 2024)

        // Get first significant word from title
        let skipWords = Set(["the", "a", "an", "on", "of", "for", "and", "in", "to", "with"])
        let titleWords = title.lowercased().components(separatedBy: " ")
        let keyword = titleWords.first(where: { !skipWords.contains($0) }) ?? "paper"
        let cleanKeyword = keyword.filter { $0.isLetter }

        return "\(cleanLastName)\(yearStr)\(cleanKeyword)"
    }

    // Generate BibTeX entry
    func bibtexEntry() -> String {
        let key = bibtexKey()
        let authorsStr = authors.joined(separator: " and ")

        let entryType = arxivId != nil ? "article" : (doi != nil ? "article" : "misc")

        var bibtex = "@\(entryType){\(key),\n"
        bibtex += "  title={\(title)},\n"
        bibtex += "  author={\(authorsStr)},\n"

        if let year = year {
            bibtex += "  year={\(year)},\n"
        }

        if let doi = doi {
            bibtex += "  doi={\(doi)},\n"
        }

        if let arxivId = arxivId {
            bibtex += "  journal={arXiv preprint arXiv:\(arxivId)},\n"
        }

        bibtex += "}"

        return bibtex
    }
}

// MARK: - Search Result

struct PaperSearchResult: Codable {
    let papers: [Paper]
    let query: String
}

// MARK: - App Configuration

struct AppConfig: Codable {
    var geminiApiKey: String
    var upstageApiKey: String
    var semanticScholarApiKey: String
    var llmProvider: String // "gemini" or "upstage"
    var geminiModel: String
    var upstageModel: String
    var temperature: Double
    var maxPapersPerSearch: Int
    var minCitationCount: Int

    static var `default`: AppConfig {
        AppConfig(
            geminiApiKey: "",
            upstageApiKey: "",
            semanticScholarApiKey: "",
            llmProvider: "gemini",
            geminiModel: "gemini-3-flash-preview",
            upstageModel: "solar-pro",
            temperature: 0.3,
            maxPapersPerSearch: 5,
            minCitationCount: 10
        )
    }

    // Save to UserDefaults
    func save() {
        if let encoded = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(encoded, forKey: "CiteAgentConfig")
        }
    }

    // Load from UserDefaults
    static func load() -> AppConfig {
        guard let data = UserDefaults.standard.data(forKey: "CiteAgentConfig"),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return config
    }
}

// MARK: - Citation Request/Response

struct CitationRequest: Codable {
    let text: String
    let context: String?
}

struct CitationResponse: Codable {
    let modifiedText: String
    let bibtexEntries: [String]
    let error: String?
}
