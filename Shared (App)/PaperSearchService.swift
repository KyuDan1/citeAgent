//
//  PaperSearchService.swift
//  CiteAgent
//
//  Semantic Scholar API integration for paper search
//

import Foundation

@available(macOS 12.0, iOS 15.0, *)
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

    // Search for papers
    func searchPapers(query: String, limit: Int = 5, minCitations: Int = 10) async throws -> [Paper] {
        let searchURL = URL(string: "\(baseURL)/paper/search")!
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: String(limit * 2)),
            URLQueryItem(name: "fields", value: "title,authors,year,citationCount,paperId,externalIds,abstract")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("CiteAgent/1.0 (Academic Research Assistant)", forHTTPHeaderField: "User-Agent")
        if let apiKey = apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        print("[PaperSearch] Searching for: '\(query)'")

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

        // Filter and convert to Paper objects
        let papers = searchResponse.data.compactMap { item -> Paper? in
            guard item.citationCount >= minCitations else { return nil }

            let authors = item.authors.map { $0.name }
            let externalIds = item.externalIds ?? ExternalIds(doi: nil, arxiv: nil)

            return Paper(
                paperId: item.paperId,
                title: item.title,
                authors: authors,
                year: item.year,
                citationCount: item.citationCount,
                doi: externalIds.doi,
                arxivId: externalIds.arxiv,
                abstract: item.abstract
            )
        }.prefix(limit).map { $0 }

        print("[PaperSearch] Found \(papers.count) papers")
        return papers
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
}

private struct Author: Codable {
    let name: String
}

private struct ExternalIds: Codable {
    let doi: String?
    let arxiv: String?

    enum CodingKeys: String, CodingKey {
        case doi = "DOI"
        case arxiv = "ArXiv"
    }
}
