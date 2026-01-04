//
//  PaperSearchService.swift
//  CiteAgent
//
//  Semantic Scholar API integration for paper search
//

import Foundation

class PaperSearchService {
    private let baseURL = "https://api.semanticscholar.org/graph/v1"
    private let apiKey: String?
    private let session: URLSession

    init(apiKey: String? = nil) {
        self.apiKey = apiKey

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    // Search for papers with preference for top conferences and recent papers
    func searchPapers(query: String, limit: Int = 5, minCitations: Int = 10, minYear: Int? = nil) async throws -> [Paper] {
        let searchURL = URL(string: "\(baseURL)/paper/search")!
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!

        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(max(limit * 4, 20))), // Get more results to filter/rank
            URLQueryItem(name: "fields", value: "title,authors,year,citationCount,paperId,externalIds,abstract,venue,publicationVenue")
        ]

        // Add year filter if specified
        if let minYear = minYear {
            queryItems.append(URLQueryItem(name: "year", value: "\(minYear)-"))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("CiteAgent/1.0 (Academic Research Assistant)", forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        print("[PaperSearch] Searching for: '\(query)' (minCitations: \(minCitations), minYear: \(minYear ?? 0))")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SearchError.invalidResponse
        }

        if httpResponse.statusCode == 429 {
            throw SearchError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw SearchError.httpError(httpResponse.statusCode)
        }

        let searchResponse = try JSONDecoder().decode(SemanticScholarResponse.self, from: data)

        let currentYear = Calendar.current.component(.year, from: Date())

        // Convert to Paper objects with scores
        var scoredPapers: [(paper: Paper, score: Double)] = searchResponse.data.compactMap { item -> (Paper, Double)? in
            // Skip papers with too few citations (unless very recent)
            let isRecent = (item.year ?? 0) >= currentYear - 2
            if item.citationCount < minCitations && !isRecent {
                return nil
            }

            let authors = item.authors.map { $0.name }
            let externalIds = item.externalIds ?? ExternalIds(doi: nil, arxiv: nil)

            let paper = Paper(
                paperId: item.paperId,
                title: item.title,
                authors: authors,
                year: item.year,
                citationCount: item.citationCount,
                doi: externalIds.doi,
                arxivId: externalIds.arxiv,
                abstract: item.abstract,
                venue: item.venue ?? item.publicationVenue?.name
            )

            let score = calculatePaperScore(paper: paper, currentYear: currentYear)
            return (paper, score)
        }

        // Sort by score (descending)
        scoredPapers.sort { $0.score > $1.score }

        // Take top results
        let papers = scoredPapers.prefix(limit).map { $0.paper }

        print("[PaperSearch] Found \(papers.count) papers (ranked by citations + recency)")
        for (index, scored) in scoredPapers.prefix(3).enumerated() {
            print("[PaperSearch]   \(index + 1). \(scored.paper.title) (\(scored.paper.year ?? 0)) - score: \(String(format: "%.1f", scored.score))")
        }

        return papers
    }

    // Calculate paper score based on recency and citations (no venue restriction)
    private func calculatePaperScore(paper: Paper, currentYear: Int) -> Double {
        var score: Double = 0

        // 1. Recency score (0-30 points)
        // Newer papers get higher scores
        if let year = paper.year {
            let age = currentYear - year
            if age <= 0 {
                score += 30 // Current year
            } else if age == 1 {
                score += 27
            } else if age == 2 {
                score += 24
            } else if age <= 4 {
                score += 18
            } else if age <= 6 {
                score += 12
            } else if age <= 10 {
                score += 6
            }
            // Papers older than 10 years get 0 recency points
        }

        // 2. Citation score (0-50 points) - increased weight since no venue score
        // Log scale for citations
        let citations = Double(paper.citationCount)
        if citations > 0 {
            let citationScore = min(50, log10(citations + 1) * 15)
            score += citationScore
        }

        return score
    }

    enum SearchError: Error {
        case invalidResponse
        case rateLimited
        case httpError(Int)
    }
}

// MARK: - Semantic Scholar API Response Models

private struct SemanticScholarResponse: Codable {
    let data: [SemanticScholarPaper]
}

private struct SemanticScholarPaper: Codable {
    let paperId: String
    let title: String
    let authors: [Author]
    let year: Int?
    let citationCount: Int
    let externalIds: ExternalIds?
    let abstract: String?
    let venue: String?
    let publicationVenue: PublicationVenue?
}

private struct Author: Codable {
    let name: String
}

private struct PublicationVenue: Codable {
    let name: String?
}

private struct ExternalIds: Codable {
    let doi: String?
    let arxiv: String?

    enum CodingKeys: String, CodingKey {
        case doi = "DOI"
        case arxiv = "ArXiv"
    }
}
