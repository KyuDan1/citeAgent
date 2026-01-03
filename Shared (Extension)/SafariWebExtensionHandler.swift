//
//  SafariWebExtensionHandler.swift
//  Shared (Extension)
//
//  Created by kyudan on 1/4/26.
//

import SafariServices
import os.log

@available(macOS 12.0, iOS 15.0, *)
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        let profile: UUID?
        if #available(iOS 17.0, macOS 14.0, *) {
            profile = request?.userInfo?[SFExtensionProfileKey] as? UUID
        } else {
            profile = request?.userInfo?["profile"] as? UUID
        }

        let message: Any?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey]
        } else {
            message = request?.userInfo?["message"]
        }

        os_log(.default, "Received message from browser.runtime.sendNativeMessage: %@ (profile: %@)", String(describing: message), profile?.uuidString ?? "none")

        // Handle different message types
        if let messageDict = message as? [String: Any],
           let action = messageDict["action"] as? String {

            handleMessage(action: action, messageDict: messageDict, context: context)
        } else {
            // Default echo response
            let response = NSExtensionItem()
            if #available(iOS 15.0, macOS 11.0, *) {
                response.userInfo = [ SFExtensionMessageKey: [ "echo": message ] ]
            } else {
                response.userInfo = [ "message": [ "echo": message ] ]
            }
            context.completeRequest(returningItems: [ response ], completionHandler: nil)
        }
    }

    private func handleMessage(action: String, messageDict: [String: Any], context: NSExtensionContext) {
        os_log(.default, "Handling action: %@", action)

        switch action {
        case "processCitation":
            handleProcessCitation(messageDict: messageDict, context: context)

        case "searchPaper":
            handleSearchPaper(messageDict: messageDict, context: context)

        case "contentScriptReady":
            let url = messageDict["url"] as? String ?? "unknown"
            os_log(.default, "Content script ready on: %@", url)
            sendResponse(["status": "acknowledged"], context: context)

        default:
            os_log(.default, "Unknown action: %@", action)
            sendResponse(["error": "Unknown action"], context: context)
        }
    }

    private func handleProcessCitation(messageDict: [String: Any], context: NSExtensionContext) {
        guard let text = messageDict["text"] as? String else {
            sendResponse(["error": "Missing text parameter"], context: context)
            return
        }

        let contextStr = messageDict["context"] as? String

        // Get API keys from message or load from defaults
        let geminiApiKey = messageDict["geminiApiKey"] as? String ?? ""
        let semanticScholarApiKey = messageDict["semanticScholarApiKey"] as? String ?? ""

        // Create config with API keys from message
        var config = AppConfig.load()
        if !geminiApiKey.isEmpty {
            config.geminiApiKey = geminiApiKey
        }
        if !semanticScholarApiKey.isEmpty {
            config.semanticScholarApiKey = semanticScholarApiKey
        }

        // Validate API key
        if config.geminiApiKey.isEmpty && config.upstageApiKey.isEmpty {
            sendResponse([
                "success": false,
                "error": "API key not configured. Please set your Gemini API key in Settings."
            ], context: context)
            return
        }

        // Create citation agent
        let agent = CitationAgentService(config: config)

        // Process text asynchronously
        Task {
            do {
                let result = try await agent.processText(text, context: contextStr)
                sendResponse([
                    "success": true,
                    "modifiedText": result.modifiedText,
                    "bibtexEntries": result.bibtexEntries
                ], context: context)
            } catch {
                os_log(.error, "Citation processing failed: %@", error.localizedDescription)
                sendResponse([
                    "success": false,
                    "error": error.localizedDescription
                ], context: context)
            }
        }
    }

    private func handleSearchPaper(messageDict: [String: Any], context: NSExtensionContext) {
        guard let query = messageDict["query"] as? String else {
            sendResponse(["error": "Missing query parameter"], context: context)
            return
        }

        let limit = messageDict["limit"] as? Int ?? 5

        let config = AppConfig.load()
        let agent = CitationAgentService(config: config)

        Task {
            do {
                let papers = try await agent.searchPaper(query: query, limit: limit)
                let papersData = papers.map { paper -> [String: Any] in
                    return [
                        "key": paper.bibtexKey(),
                        "title": paper.title,
                        "authors": Array(paper.authors.prefix(3)),
                        "year": paper.year ?? 0,
                        "citations": paper.citationCount
                    ]
                }
                sendResponse([
                    "success": true,
                    "papers": papersData
                ], context: context)
            } catch {
                os_log(.error, "Paper search failed: %@", error.localizedDescription)
                sendResponse([
                    "success": false,
                    "error": error.localizedDescription
                ], context: context)
            }
        }
    }

    private func sendResponse(_ responseDict: [String: Any], context: NSExtensionContext) {
        let response = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            response.userInfo = [ SFExtensionMessageKey: responseDict ]
        } else {
            response.userInfo = [ "message": responseDict ]
        }
        context.completeRequest(returningItems: [ response ], completionHandler: nil)
    }
}
