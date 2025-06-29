//
//  ContentView.swift
//  LLMtest
//
//  Created by Carter Gregg on 6/25/25.
//

import SwiftUI
import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif
#if os(iOS)
import UIKit
#endif

// MARK: - Download Delegate
class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let filename: String
    let progressCallback: (Double) -> Void
    
    init(filename: String, progressCallback: @escaping (Double) -> Void) {
        self.filename = filename
        self.progressCallback = progressCallback
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressCallback(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        progressCallback(1.0)
    }
}

// MARK: - Web Search Service
class WebSearchService {
    static let shared = WebSearchService()
    
    private init() {}
    
    func searchWeb(query: String) async -> String {
        // Use DuckDuckGo Instant Answer API (no API key required)
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.duckduckgo.com/?q=\(encodedQuery)&format=json&no_html=1&skip_disambig=1") else {
            return "Unable to search for: \(query)"
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try to get instant answer first
                if let abstract = json["Abstract"] as? String, !abstract.isEmpty {
                    let source = json["AbstractSource"] as? String ?? "DuckDuckGo"
                    let truncatedAbstract = truncateText(abstract, maxLength: 300)
                    return "Search: \(truncatedAbstract) (Source: \(source))"
                }
                
                // Try definition
                if let definition = json["Definition"] as? String, !definition.isEmpty {
                    let source = json["DefinitionSource"] as? String ?? "Dictionary"
                    let truncatedDefinition = truncateText(definition, maxLength: 200)
                    return "Definition: \(truncatedDefinition) (Source: \(source))"
                }
                
                // Try related topics
                if let relatedTopics = json["RelatedTopics"] as? [[String: Any]], !relatedTopics.isEmpty {
                    var results = "Search results: "
                    for (index, topic) in relatedTopics.prefix(2).enumerated() {
                        if let text = topic["Text"] as? String, !text.isEmpty {
                            let truncatedText = truncateText(text, maxLength: 150)
                            results += "\(index + 1). \(truncatedText) "
                        }
                    }
                    return results
                }
                
                // Fallback to answer if available
                if let answer = json["Answer"] as? String, !answer.isEmpty {
                    let truncatedAnswer = truncateText(answer, maxLength: 200)
                    return "Answer: \(truncatedAnswer)"
                }
            }
            
            // If no structured data, try a simple web search fallback
            return await fallbackWebSearch(query: query)
            
        } catch {
            return "Search error: Unable to fetch results for '\(query)'. Please try rephrasing your query."
        }
    }
    
    private func truncateText(_ text: String, maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        let truncated = String(text.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
    
    private func fallbackWebSearch(query: String) async -> String {
        // Simplified fallback - just return a message that search was attempted
        return "Search attempted for '\(query)' but no detailed results available. Please try a more specific query."
    }
    

}

struct Message: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(content: String, isUser: Bool, timestamp: Date) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = timestamp
    }
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    let createdAt: Date
    var lastUpdated: Date
    
    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.lastUpdated = Date()
    }
}

struct ModelInfo: Hashable {
    let filename: String
    let displayName: String
    let description: String
    let contextSize: Int32
    let promptFormat: PromptFormat
    let sizeGB: Double // Size in GB
}

struct StorageInfo {
    var totalSpace: Int64 = 0
    var usedSpace: Int64 = 0
    var availableSpace: Int64 = 0
    var appUsage: Int64 = 0
    var modelUsage: Int64 = 0
    
    var usedPercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(totalSpace)
    }
    
    var appUsagePercentage: Double {
        guard totalSpace > 0 else { return 0 }
        return Double(appUsage) / Double(totalSpace)
    }
}

enum PromptFormat: Hashable {
    case chatml
    case alpaca
    case phi3
    case llama2
    case llama3
    case mistral
}

class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var showSettings = false
    @Published var contextWarning: String? = nil
    @Published var webSearchEnabled: Bool = true
    @Published var isSearching: Bool = false
    @Published var downloadProgress: [String: Double] = [:] // Model filename -> progress
    @Published var downloadingModels: Set<String> = []
    @Published var storageInfo: StorageInfo = StorageInfo()
    @Published var selectedModel: ModelInfo = ModelInfo(
        filename: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
        displayName: "TinyLlama 1.1B",
        description: "Fast, memory-efficient model",
        contextSize: 512,
        promptFormat: .chatml,
        sizeGB: 0.7
    )
    
    let availableModels = [
        ModelInfo(
            filename: "tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf",
            displayName: "TinyLlama 1.1B (Fast)",
            description: "Smallest model, very fast but limited capabilities",
            contextSize: 2048,
            promptFormat: .chatml,
            sizeGB: 0.7
        ),
        ModelInfo(
            filename: "phi-3-mini-4k-instruct.Q4_K_M.gguf",
            displayName: "Phi-3 Mini 3.8B (Balanced)",
            description: "Microsoft's efficient model, good balance of speed and quality",
            contextSize: 4096,
            promptFormat: .phi3,
            sizeGB: 2.3
        ),
        ModelInfo(
            filename: "llama-3.2-3b-instruct-q4_k_m.gguf",
            displayName: "Llama 3.2 3B (Good)",
            description: "Meta's latest 3B model with excellent reasoning",
            contextSize: 8192,
            promptFormat: .llama3,
            sizeGB: 1.9
        ),
        ModelInfo(
            filename: "qwen2.5-7b-instruct-q4_k_m.gguf",
            displayName: "Qwen 2.5 7B (Great)",
            description: "Alibaba's powerful 7B model with huge context window",
            contextSize: 32768,
            promptFormat: .chatml,
            sizeGB: 4.1
        ),
        ModelInfo(
            filename: "llama-3.1-8b-instruct-q4_k_m.gguf",
            displayName: "Llama 3.1 8B (Superior)",
            description: "Meta's 8B model with massive 32K context window",
            contextSize: 32768,
            promptFormat: .llama3,
            sizeGB: 4.6
        ),
        ModelInfo(
            filename: "mistral-nemo-12b-instruct-2407-q4_k_m.gguf",
            displayName: "Mistral Nemo 12B (Premium)",
            description: "Mistral's advanced 12B model with excellent reasoning",
            contextSize: 32768,
            promptFormat: .mistral,
            sizeGB: 7.2
        ),
        ModelInfo(
            filename: "qwen2.5-14b-instruct-q4_k_m.gguf",
            displayName: "Qwen 2.5 14B (Outstanding)",
            description: "Alibaba's flagship 14B model, exceptional performance",
            contextSize: 32768,
            promptFormat: .chatml,
            sizeGB: 8.2
        ),
        ModelInfo(
            filename: "qwen2.5-32b-instruct-q4_k_m.gguf",
            displayName: "Qwen 2.5 32B (Ultimate)",
            description: "Massive 32B model, near GPT-4 level performance",
            contextSize: 32768,
            promptFormat: .chatml,
            sizeGB: 18.0
        )
    ]
    
    init() {
        loadConversations()
        if conversations.isEmpty {
            createNewConversation()
        } else {
            currentConversation = conversations.first
        }
        Task { @MainActor in
            updateStorageInfo()
        }
    }
    
    func createNewConversation() {
        let newConversation = Conversation()
        conversations.insert(newConversation, at: 0)
        currentConversation = newConversation
        saveConversations()
    }
    
    func deleteConversation(_ conversation: Conversation) {
        conversations.removeAll { $0.id == conversation.id }
        if currentConversation?.id == conversation.id {
            currentConversation = conversations.first ?? Conversation()
            if conversations.isEmpty {
                conversations.append(currentConversation!)
            }
        }
        saveConversations()
    }
    
    func selectConversation(_ conversation: Conversation) {
        currentConversation = conversation
    }
    
    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              var conversation = currentConversation else { return }
        
        let userMessage = Message(content: inputText, isUser: true, timestamp: Date())
        conversation.messages.append(userMessage)
        conversation.lastUpdated = Date()
        
        // Update title if this is the first message
        if conversation.messages.count == 1 {
            conversation.title = String(inputText.prefix(30)) + (inputText.count > 30 ? "..." : "")
        }
        
        updateCurrentConversation(conversation)
        
        let messageToSend = inputText
        inputText = ""
        isLoading = true
        
        Task {
            await sendToLLM(message: messageToSend)
        }
    }
    
    private func updateCurrentConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[index] = conversation
            currentConversation = conversation
            saveConversations()
        }
    }
    
    private func truncateHistoryForContext(_ messages: [Message], maxTokens: Int32) -> [Message] {
        // Reserve tokens for the current message and response
        let reservedTokens = Int32(150) // Reserve space for current message + response
        let availableTokens = maxTokens - reservedTokens
        
        // Rough estimate: 1 token ≈ 4 characters (conservative)
        let maxCharacters = Int(availableTokens * 3) // Conservative estimate
        
        var totalCharacters = 0
        var truncatedHistory: [Message] = []
        
        // Work backwards through messages, excluding the last one (current user message)
        let historyMessages = Array(messages.dropLast())
        
        for message in historyMessages.reversed() {
            let messageLength = message.content.count + 20 // Add overhead for formatting
            
            if totalCharacters + messageLength <= maxCharacters {
                truncatedHistory.insert(message, at: 0)
                totalCharacters += messageLength
            } else {
                break
            }
        }
        
        // If we have too many messages, keep only the most recent ones
        if truncatedHistory.count > 6 {
            truncatedHistory = Array(truncatedHistory.suffix(6))
        }
        
        return truncatedHistory
    }
    
    private func needsWebSearch(message: String) -> Bool {
        let lowercased = message.lowercased()
        
        // Keywords that indicate current/recent information is needed
        let currentInfoKeywords = [
            "today", "now", "current", "latest", "recent", "this year", "2024", "2025",
            "what's happening", "news", "update", "currently", "at the moment",
            "stock price", "weather", "temperature"
        ]
        
        // Question patterns that often need web search
        let searchPatterns = [
            "what is the", "what are the", "who is", "when did", "when will",
            "how much", "what happened", "tell me about", "information about",
            "facts about", "details about", "explain", "define"
        ]
        
        // Check for current info keywords
        for keyword in currentInfoKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }
        
        // Check for search patterns
        for pattern in searchPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }
        
        // Check for question marks (likely questions that might need search)
        if lowercased.contains("?") && lowercased.count > 10 {
            return true
        }
        
        return false
    }
    
    private func extractSearchQuery(from message: String) -> String {
        // Clean up the message to create a good search query
        var query = message
        
        // Remove common question words that don't help search
        let removeWords = ["please", "can you", "could you", "tell me", "what is", "what are", 
                          "who is", "when did", "when will", "how much", "explain", "define"]
        
        for word in removeWords {
            query = query.replacingOccurrences(of: word, with: "", options: .caseInsensitive)
        }
        
        // Clean up punctuation and extra spaces
        query = query.replacingOccurrences(of: "?", with: "")
        query = query.replacingOccurrences(of: "!", with: "")
        query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        query = query.replacingOccurrences(of: "  ", with: " ")
        
        // If query is too short, use original message
        if query.count < 3 {
            query = message.replacingOccurrences(of: "?", with: "")
        }
        
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    @MainActor
    private func sendToLLM(message: String) async {
        guard var conversation = currentConversation else {
            isLoading = false
            return
        }
        
        // Try to find model file - first in Documents, then in bundle
        var modelPath: String?
        
        // Check Documents directory first (downloaded models)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let documentsModelPath = documentsPath.appendingPathComponent(selectedModel.filename).path
        
        if FileManager.default.fileExists(atPath: documentsModelPath) {
            modelPath = documentsModelPath
        } else {
            // Check app bundle
            let resourceName = selectedModel.filename.hasSuffix(".gguf") ? 
                String(selectedModel.filename.dropLast(5)) : selectedModel.filename
            modelPath = Bundle.main.path(forResource: resourceName, ofType: "gguf")
        }
        
        guard let finalModelPath = modelPath else {
            let errorMessage = Message(
                content: "Model file '\(selectedModel.displayName)' not found. Please download the model first.",
                isUser: false,
                timestamp: Date()
            )
            if var conv = currentConversation {
                conv.messages.append(errorMessage)
                updateCurrentConversation(conv)
            }
            isLoading = false
            return
        }
        
        // Check if web search is needed and enabled
        var searchResults = ""
        if webSearchEnabled && needsWebSearch(message: message) {
            isSearching = true
            let searchQuery = extractSearchQuery(from: message)
            searchResults = await WebSearchService.shared.searchWeb(query: searchQuery)
            isSearching = false
        }
        
        // Build conversation context with intelligent truncation, accounting for search results
        let searchTokens = searchResults.count / 4 // Rough estimate
        let availableTokens = Int(selectedModel.contextSize) - searchTokens - 100 // Reserve space for search + response
        let conversationHistory = truncateHistoryForContext(conversation.messages, maxTokens: Int32(max(100, availableTokens)))
        let prompt = buildPrompt(currentMessage: message, history: conversationHistory, searchResults: searchResults)
        
        // Check context usage and warn user
        let estimatedTokens = prompt.count / 4 // Rough estimate
        let contextUsage = Double(estimatedTokens) / Double(selectedModel.contextSize)
        
        if contextUsage > 0.7 {
            contextWarning = "Context is \(Int(contextUsage * 100))% full. Consider starting a new conversation soon."
        } else {
            contextWarning = nil
        }
        
        let response = LlamaWrapper.shared.runInference(prompt: prompt, modelPath: finalModelPath)
        let cleanedResponse = cleanResponse(response, format: selectedModel.promptFormat)
        
        let assistantMessage = Message(
            content: cleanedResponse,
            isUser: false,
            timestamp: Date()
        )
        
        conversation.messages.append(assistantMessage)
        conversation.lastUpdated = Date()
        updateCurrentConversation(conversation)
        isLoading = false
    }
    
    private func buildPrompt(currentMessage: String, history: [Message], searchResults: String = "") -> String {
        switch selectedModel.promptFormat {
        case .phi3:
            // Phi-3 with ultra-strict anti-hallucination instructions
            var prompt = "You are a factual assistant with access to web search. You must be completely accurate. Use the search results when available to provide current and accurate information.\n\n"
            
            // Add search results if available
            if !searchResults.isEmpty {
                prompt += "SEARCH INFO: \(searchResults)\n\n"
            }
            
            // Add conversation history
            for message in history {
                if message.isUser {
                    prompt += "User: \(message.content)\n"
                } else {
                    prompt += "Assistant: \(message.content)\n"
                }
            }
            
            // Add current message with strong reminder
            if !searchResults.isEmpty {
                prompt += "User: \(currentMessage)\nAssistant: Based on the search info:"
            } else {
                prompt += "User: \(currentMessage)\nAssistant: I will provide only accurate, verified information:"
            }
            return prompt
            
        case .chatml:
            // TinyLlama with web search capabilities
            var prompt = "<|im_start|>system\nYou are a helpful assistant with web search access. Use search results when provided to give accurate, current information. Be honest if you don't know something.<|im_end|>\n"
            
            // Add search results if available
            if !searchResults.isEmpty {
                prompt += "<|im_start|>system\nSEARCH: \(searchResults)<|im_end|>\n"
            }
            
            // Add conversation history  
            for message in history {
                if message.isUser {
                    prompt += "<|im_start|>user\n\(message.content)<|im_end|>\n"
                } else {
                    prompt += "<|im_start|>assistant\n\(message.content)<|im_end|>\n"
                }
            }
            
            // Add current message
            prompt += "<|im_start|>user\n\(currentMessage)<|im_end|>\n<|im_start|>assistant\n"
            return prompt
            
        case .alpaca:
            let instruction = history.isEmpty ? currentMessage : 
                "Previous conversation:\n" + history.map { "\($0.isUser ? "Human" : "Assistant"): \($0.content)" }.joined(separator: "\n") + 
                "\n\nCurrent question: \(currentMessage)"
            
            return "### Instruction:\n\(instruction)\n\n### Response:\n"
            
        case .llama2:
            var prompt = "<s>[INST] <<SYS>>\nYou are a helpful AI assistant.\n<</SYS>>\n\n"
            
            for message in history {
                if message.isUser {
                    prompt += "\(message.content) [/INST] "
                } else {
                    prompt += "\(message.content) </s><s>[INST] "
                }
            }
            
            prompt += "\(currentMessage) [/INST] "
            return prompt
            
        case .llama3:
            // Llama 3.x format with system message
            var prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\nYou are a helpful AI assistant with web search capabilities. Use search results when provided to give accurate, current information."
            
            // Add search results if available
            if !searchResults.isEmpty {
                prompt += " SEARCH INFO: \(searchResults)"
            }
            
            prompt += "<|eot_id|>"
            
            // Add conversation history
            for message in history {
                if message.isUser {
                    prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(message.content)<|eot_id|>"
                } else {
                    prompt += "<|start_header_id|>assistant<|end_header_id|>\n\n\(message.content)<|eot_id|>"
                }
            }
            
            // Add current message
            prompt += "<|start_header_id|>user<|end_header_id|>\n\n\(currentMessage)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"
            return prompt
            
        case .mistral:
            // Mistral format with system message
            var prompt = "<s>[INST]"
            
            // Add system message with search results
            if !searchResults.isEmpty {
                prompt += " You are a helpful assistant with web search access. SEARCH INFO: \(searchResults)\n\n"
            } else {
                prompt += " You are a helpful assistant.\n\n"
            }
            
            // Add conversation history
            for message in history {
                if message.isUser {
                    prompt += "\(message.content) [/INST] "
                } else {
                    prompt += "\(message.content) </s><s>[INST] "
                }
            }
            
            prompt += "\(currentMessage) [/INST]"
            return prompt
        }
    }
    
    private func cleanResponse(_ response: String, format: PromptFormat) -> String {
        var cleaned = response
        
        // Remove common artifacts based on format
        let stopTokens: [String]
        switch format {
        case .phi3:
            stopTokens = ["User:", "Assistant:", "\n\n", "Human:", "<|end|>", "I'll provide a factual"]
        case .chatml:
            stopTokens = ["<|im_end|>", "<|im_start|>", "user\n", "assistant\n", "system\n"]
        case .alpaca:
            stopTokens = ["### Instruction:", "### Response:"]
        case .llama2:
            stopTokens = ["[/INST]", "</s>", "<s>", "[INST]"]
        case .llama3:
            stopTokens = ["<|eot_id|>", "<|start_header_id|>", "<|end_header_id|>", "<|begin_of_text|>"]
        case .mistral:
            stopTokens = ["[/INST]", "</s>", "<s>", "[INST]"]
        }
        
        // Stop at first occurrence of any stop token
        for token in stopTokens {
            if let range = cleaned.range(of: token) {
                cleaned = String(cleaned[..<range.lowerBound])
            }
        }
        
        // Clean up formatting
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // HALLUCINATION DETECTION & PREVENTION
        let hallucinationPatterns = [
            // Placeholder patterns
            "[Your ", "[Insert ", "[Provide ", "[Add ", "[Include ",
            "{{", "}}", "[placeholder", "[PLACEHOLDER", 
            "lorem ipsum", "Lorem Ipsum", "example.com",
            "[content]", "[Content]", "[text]", "[Text]",
            
            // Suspicious specificity without context
            "According to my database", "Based on my training data",
            "In my experience", "I remember", "I recall",
            "Studies show that exactly", "Research indicates that precisely",
            
            // Made-up citations
            "According to Dr. ", "Professor ", " University study",
            "published in 20", "research from 20", "study conducted in 20",
            
            // Overly confident statements about uncertain things
            "I can confirm that", "It is definitely", "I guarantee",
            "Without a doubt", "Absolutely certain", "100% sure",
            
            // Repetitive or nonsensical patterns
            "As an AI", "I am an AI", "my instructions", "my training",
            "I cannot", "I'm not able", "I don't have access",
            
            // Specific geographical errors
            "seattle is in texas", "seattle is located in texas", "seattle texas",
            "paris is in germany", "london is in france", "tokyo is in china",
            "new york is in california", "los angeles is in florida"
        ]
        
        var isHallucination = false
        var hallucinationType = ""
        
        for pattern in hallucinationPatterns {
            if cleaned.lowercased().contains(pattern.lowercased()) {
                isHallucination = true
                hallucinationType = pattern
                break
            }
        }
        
        // Check for specific number/date hallucinations
        let dateRegex = try? NSRegularExpression(pattern: "\\b(19|20)\\d{2}\\b")
        let numberRegex = try? NSRegularExpression(pattern: "\\b\\d{4,}\\b") // 4+ digit numbers
        
        if let dateRegex = dateRegex {
            let matches = dateRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            if matches.count > 2 { // Multiple specific dates = suspicious
                isHallucination = true
                hallucinationType = "multiple specific dates"
            }
        }
        
        if let numberRegex = numberRegex {
            let matches = numberRegex.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            if matches.count > 3 { // Multiple large numbers = suspicious
                isHallucination = true
                hallucinationType = "multiple specific numbers"
            }
        }
        
        // Check for repetitive content
        let words = cleaned.components(separatedBy: .whitespacesAndNewlines)
        let wordCount = words.count
        let uniqueWords = Set(words)
        
        if wordCount > 10 && Double(uniqueWords.count) / Double(wordCount) < 0.3 {
            isHallucination = true
            hallucinationType = "repetitive content"
        }
        
        // If hallucination detected, provide safe fallback
        if isHallucination {
            print("🚨 Hallucination detected: \(hallucinationType)")
            return "I want to be accurate, so I should clarify that I'm not certain about the specific details you're asking about. Could you help me understand what specific information you need?"
        }
        
        // Remove repetitive patterns
        let lines = cleaned.components(separatedBy: .newlines)
        var uniqueLines: [String] = []
        var lastLine = ""
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine != lastLine && !trimmedLine.isEmpty {
                uniqueLines.append(line)
                lastLine = trimmedLine
            }
        }
        
        let result = uniqueLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Final quality checks
        if result.count < 10 {
            return "I'm not sure how to respond to that. Could you provide more context or rephrase your question?"
        }
        
        if result.contains("I am an AI") || result.contains("my instructions") || result.contains("my training") {
            return "I'm here to help with your question. What specific information are you looking for?"
        }
        
        return result
    }
    
    func exportConversation(_ conversation: Conversation) {
        #if os(macOS)
        let panel = NSSavePanel()
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [UTType.plainText]
        } else {
            panel.allowedFileTypes = ["txt"]
        }
        panel.nameFieldStringValue = "\(conversation.title).txt"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let content = self.formatConversationForExport(conversation)
                try? content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #else
        // iOS export - save to Documents and show share sheet
        let content = formatConversationForExport(conversation)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent("\(conversation.title).txt")
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            // On iOS, you could show a share sheet here
            print("Conversation exported to: \(fileURL.path)")
        } catch {
            print("Export failed: \(error)")
        }
        #endif
    }
    
    private func formatConversationForExport(_ conversation: Conversation) -> String {
        var content = "Conversation: \(conversation.title)\n"
        content += "Created: \(DateFormatter.localizedString(from: conversation.createdAt, dateStyle: .medium, timeStyle: .short))\n"
        content += "Last Updated: \(DateFormatter.localizedString(from: conversation.lastUpdated, dateStyle: .medium, timeStyle: .short))\n"
        content += "Model: \(selectedModel.displayName)\n\n"
        content += String(repeating: "=", count: 50) + "\n\n"
        
        for message in conversation.messages {
            let sender = message.isUser ? "You" : "Assistant"
            let timestamp = DateFormatter.localizedString(from: message.timestamp, dateStyle: .none, timeStyle: .short)
            content += "[\(timestamp)] \(sender):\n\(message.content)\n\n"
        }
        
        return content
    }
    
    private func saveConversations() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: "conversations")
        }
    }
    
    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "conversations"),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            conversations = decoded
        }
    }
    
    @MainActor
    func downloadModel(_ model: ModelInfo) async {
        let filename = model.filename
        downloadingModels.insert(filename)
        downloadProgress[filename] = 0.0
        
        // Model download URLs
        let downloadURLs: [String: String] = [
            "llama-3.2-3b-instruct-q4_k_m.gguf": "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            "qwen2.5-7b-instruct-q4_k_m.gguf": "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
            "llama-3.1-8b-instruct-q4_k_m.gguf": "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf",
            "mistral-nemo-12b-instruct-2407-q4_k_m.gguf": "https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf",
            "qwen2.5-14b-instruct-q4_k_m.gguf": "https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf",
            "qwen2.5-32b-instruct-q4_k_m.gguf": "https://huggingface.co/bartowski/Qwen2.5-32B-Instruct-GGUF/resolve/main/Qwen2.5-32B-Instruct-Q4_K_M.gguf"
        ]
        
        guard let urlString = downloadURLs[filename],
              let url = URL(string: urlString) else {
            downloadingModels.remove(filename)
            downloadProgress.removeValue(forKey: filename)
            return
        }
        
        do {
            // Get documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent(filename)
            
            // Check if file already exists
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                downloadingModels.remove(filename)
                downloadProgress.removeValue(forKey: filename)
                return
            }
            
            // Create download task with real progress tracking
            let delegate = DownloadDelegate(filename: filename) { progress in
                Task { @MainActor in
                    self.downloadProgress[filename] = progress
                }
            }
            
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempURL, response) = try await session.download(from: url)
            
            // Validate the response
            if let httpResponse = response as? HTTPURLResponse {
                guard httpResponse.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
            }
            
            // Validate file size (should be at least 1MB for a real model)
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            guard fileSize > 1_000_000 else { // At least 1MB
                throw URLError(.zeroByteResource)
            }
            
            // Validate GGUF header without loading entire file
            let handle = try FileHandle(forReadingFrom: tempURL)
            defer { try? handle.close() }
            let headerData = try handle.read(upToCount: 4) ?? Data()
            guard headerData == Data([0x47, 0x47, 0x55, 0x46]) else { // "GGUF" magic bytes
                throw URLError(.cannotParseResponse)
            }
            
            // Move file to final destination
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
            
            // Copy to app bundle for immediate use
            let bundlePath = Bundle.main.bundleURL.appendingPathComponent(filename)
            try? FileManager.default.copyItem(at: destinationURL, to: bundlePath)
            
            downloadingModels.remove(filename)
            downloadProgress.removeValue(forKey: filename)
            updateStorageInfo() // Update storage info after successful download
            
        } catch {
            print("Download failed: \(error)")
            downloadingModels.remove(filename)
            downloadProgress.removeValue(forKey: filename)
            
            // Show user-friendly error message
            let errorMessage = switch error {
            case URLError.badServerResponse:
                "Server returned an error. Please try again later."
            case URLError.zeroByteResource:
                "Downloaded file is too small or corrupted. Please try again."
            case URLError.cannotParseResponse:
                "Downloaded file is not a valid model file. Please try again."
            case URLError.notConnectedToInternet:
                "No internet connection. Please check your network and try again."
            default:
                "Download failed: \(error.localizedDescription)"
            }
            
            // You could add an alert here to show the error to the user
            print("User-friendly error: \(errorMessage)")
        }
    }
    
    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let modelPath = documentsPath.appendingPathComponent(model.filename)
        return FileManager.default.fileExists(atPath: modelPath.path) || 
               Bundle.main.path(forResource: model.filename.replacingOccurrences(of: ".gguf", with: ""), ofType: "gguf") != nil
    }
    
    @MainActor
    func updateStorageInfo() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            // Get system storage info
            let systemAttributes = try FileManager.default.attributesOfFileSystem(forPath: documentsPath.path)
            if let totalSpace = systemAttributes[.systemSize] as? Int64,
               let freeSpace = systemAttributes[.systemFreeSize] as? Int64 {
                storageInfo.totalSpace = totalSpace
                storageInfo.availableSpace = freeSpace
                storageInfo.usedSpace = totalSpace - freeSpace
            }
            
            // Calculate app usage
            var appUsage: Int64 = 0
            var modelUsage: Int64 = 0
            
            // Check Documents directory for downloaded models
            if let enumerator = FileManager.default.enumerator(at: documentsPath, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        appUsage += Int64(fileSize)
                        if fileURL.pathExtension == "gguf" {
                            modelUsage += Int64(fileSize)
                        }
                    }
                }
            }
            
            // Check bundle for included models
            if let bundlePath = Bundle.main.resourcePath {
                let bundleURL = URL(fileURLWithPath: bundlePath)
                if let enumerator = FileManager.default.enumerator(at: bundleURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) {
                    for case let fileURL as URL in enumerator {
                        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            if fileURL.pathExtension == "gguf" {
                                appUsage += Int64(fileSize)
                                modelUsage += Int64(fileSize)
                            }
                        }
                    }
                }
            }
            
            storageInfo.appUsage = appUsage
            storageInfo.modelUsage = modelUsage
            
        } catch {
            print("Error calculating storage: \(error)")
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showingSidebar = true
    @State private var selectedConversationId: UUID? = nil
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            // Conversations list for iOS
            VStack {
                List(viewModel.conversations) { conversation in
                    NavigationLink(
                        destination: chatView(for: conversation),
                        tag: conversation.id,
                        selection: $selectedConversationId
                    ) {
                        ConversationRow(
                            conversation: conversation,
                            onDelete: { viewModel.deleteConversation(conversation) },
                            onExport: { viewModel.exportConversation(conversation) }
                        )
                    }
                }
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { viewModel.showSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            viewModel.createNewConversation()
                            // Automatically navigate to the new conversation
                            if let newConversation = viewModel.currentConversation {
                                selectedConversationId = newConversation.id
                            }
                        }) {
                            Image(systemName: "plus")
                        }
                    }
                }
                .onAppear {
                    // Set initial selection if we have conversations
                    if selectedConversationId == nil, let firstConversation = viewModel.conversations.first {
                        selectedConversationId = firstConversation.id
                        viewModel.selectConversation(firstConversation)
                    }
                }
                .onChange(of: selectedConversationId) { newId in
                    if let newId = newId,
                       let conversation = viewModel.conversations.first(where: { $0.id == newId }) {
                        viewModel.selectConversation(conversation)
                    }
                }
            }
            
            // Default detail view for iOS when no conversation is selected
            VStack {
                Image(systemName: "message.circle")
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
                Text("Select a conversation or create a new one")
                    .font(.title2)
                    .foregroundColor(.secondary)
                Button("Create New Chat") {
                    viewModel.createNewConversation()
                    if let newConversation = viewModel.currentConversation {
                        selectedConversationId = newConversation.id
                    }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
            .navigationTitle("LLM Chat")
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle()) // Force two-column layout
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
        #else
        // macOS version with NavigationSplitView
        NavigationSplitView {
            // Sidebar with conversations
            VStack {
                HStack {
                    Text("Conversations")
                        .font(.headline)
                    Spacer()
                    Button(action: viewModel.createNewConversation) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
                .padding()
                
                List(viewModel.conversations, selection: Binding<Conversation.ID?>(
                    get: { viewModel.currentConversation?.id },
                    set: { id in
                        if let id = id,
                           let conversation = viewModel.conversations.first(where: { $0.id == id }) {
                            viewModel.selectConversation(conversation)
                        }
                    }
                )) { conversation in
                    ConversationRow(
                        conversation: conversation,
                        onDelete: { viewModel.deleteConversation(conversation) },
                        onExport: { viewModel.exportConversation(conversation) }
                    )
                }
            }
        } detail: {
            // Main chat view
            VStack {
                if let conversation = viewModel.currentConversation {
                    chatView(for: conversation)
                } else {
                    VStack {
                        Image(systemName: "message.circle")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("Select a conversation or create a new one")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(viewModel.currentConversation?.title ?? "LLM Chat")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { viewModel.showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
        #endif
    }
    
    @ViewBuilder
    private func chatView(for conversation: Conversation) -> some View {
        VStack {
            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if viewModel.isSearching {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("🔍 Searching the web...")
                                    .foregroundColor(.blue)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
                .onChange(of: conversation.messages.count) {
                    if let lastMessage = conversation.messages.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Context warning
            if let warning = viewModel.contextWarning {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("New Chat") {
                        viewModel.createNewConversation()
                        viewModel.contextWarning = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
            
            // Input area
            VStack(spacing: 0) {
                Divider()
                HStack {
                    TextField("Type your message...", text: $viewModel.inputText, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(1...4)
                        .disabled(viewModel.isLoading)
                        .onSubmit {
                            if !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                viewModel.sendMessage()
                            }
                        }
                    
                    Button(action: viewModel.sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading ? .gray : .blue)
                    }
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                }
                .padding()
            }
            .background(backgroundColorCompat)
        }
        #if os(iOS)
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    private var backgroundColorCompat: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.systemGroupedBackground)
        #endif
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let onDelete: () -> Void
    let onExport: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conversation.title)
                .font(.headline)
                .lineLimit(1)
            
            Text("\(conversation.messages.count) messages")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(conversation.lastUpdated, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .contextMenu {
            Button("Export", action: onExport)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        #if os(iOS)
        NavigationView {
            settingsContent
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        #else
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(backgroundColorCompat)
            
            Divider()
            
            settingsContent
        }
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
    
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modelSelectionSection
                downloadInfoSection
                webSearchSection
                modelInfoSection
                performanceSection
            }
            .padding()
        }
    }
    
    private var backgroundColorCompat: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemGroupedBackground)
        #endif
    }
    
    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Selection")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                ForEach(viewModel.availableModels, id: \.filename) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(model.displayName)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(String(format: "%.1f", model.sizeGB)) GB")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            Text(model.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        // Download status and button
                        HStack(spacing: 8) {
                            if viewModel.isModelDownloaded(model) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            } else if viewModel.downloadingModels.contains(model.filename) {
                                VStack(spacing: 2) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    if let progress = viewModel.downloadProgress[model.filename] {
                                        Text("\(Int(progress * 100))%")
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                    }
                                }
                            } else {
                                Button(action: {
                                    Task {
                                        await viewModel.downloadModel(model)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.down.circle.fill")
                                        Text("Download")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                            
                            if viewModel.selectedModel.filename == model.filename {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.selectedModel.filename == model.filename ? 
                                  Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if viewModel.isModelDownloaded(model) {
                            viewModel.selectedModel = model
                        }
                    }
                }
            }
        }
    }
    
    private var downloadInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage & Downloads")
                .font(.headline)
                .foregroundColor(.primary)
            
            // System Storage Bar
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("System Storage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(formatBytes(viewModel.storageInfo.usedSpace)) / \(formatBytes(viewModel.storageInfo.totalSpace))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 8)
                        
                        // Used space bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(storageColor(for: viewModel.storageInfo.usedPercentage))
                            .frame(width: geometry.size.width * viewModel.storageInfo.usedPercentage, height: 8)
                    }
                }
                .frame(height: 8)
                
                Text("\(Int(viewModel.storageInfo.usedPercentage * 100))% full • \(formatBytes(viewModel.storageInfo.availableSpace)) available")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // LLM App Usage
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(.purple)
                    Text("LLM App Usage")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text(formatBytes(viewModel.storageInfo.appUsage))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("AI Models:")
                        .font(.caption)
                    Spacer()
                    Text(formatBytes(viewModel.storageInfo.modelUsage))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.purple)
                }
                
                // Model breakdown
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(viewModel.availableModels.filter { viewModel.isModelDownloaded($0) }, id: \.filename) { model in
                        HStack {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text(model.displayName)
                                .font(.caption2)
                            Spacer()
                            Text("\(String(format: "%.1f", model.sizeGB)) GB")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Divider()
            
            // Download Status
            VStack(alignment: .leading, spacing: 8) {
                if viewModel.downloadingModels.isEmpty {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Click 'Download' next to any model to get it. Large models provide much better understanding and responses.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Downloading \(viewModel.downloadingModels.count) model(s)...")
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    ForEach(Array(viewModel.downloadingModels), id: \.self) { filename in
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(filename)
                                .font(.caption2)
                            Spacer()
                            if let progress = viewModel.downloadProgress[filename] {
                                Text("\(Int(progress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                
                Text("💡 Tip: Qwen 2.5 7B offers the best balance of quality and performance for most users.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
        .onAppear {
            viewModel.updateStorageInfo()
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func storageColor(for percentage: Double) -> Color {
        switch percentage {
        case 0..<0.7:
            return .green
        case 0.7..<0.85:
            return .orange
        default:
            return .red
        }
    }
    
    private var webSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Web Search")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Enable Web Search", isOn: $viewModel.webSearchEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                Text("When enabled, the assistant can search the web for current information, news, weather, and factual data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if viewModel.webSearchEnabled {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                        Text("🔍 Web search active - Ask about current events, weather, or recent information!")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.1))
        )
    }
    
    private var modelInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Model Info")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Model: \(viewModel.selectedModel.displayName)")
                Text("Description: \(viewModel.selectedModel.description)")
                Text("Context Size: \(viewModel.selectedModel.contextSize) tokens")
                Text("Format: \(String(describing: viewModel.selectedModel.promptFormat))")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("• Phi-3 Mini provides much better response quality")
                Text("• TinyLlama is faster but less accurate")
                Text("• All models run locally on your Mac")
                Text("• GPU acceleration enabled with Metal")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.05))
            )
        }
    }
}

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .clipShape(RoundedCorner(radius: 4, corners: [.topLeft, .topRight, .bottomLeft]))
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.primary)
                        .cornerRadius(18)
                        .clipShape(RoundedCorner(radius: 4, corners: [.topLeft, .topRight, .bottomRight]))
                    
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }
}

extension View {
    func customCornerRadius(_ radius: CGFloat, corners: RectCorner = .allCorners) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        }
        
        return path
    }
}

#Preview {
    ContentView()
}
