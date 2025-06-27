//
//  Config.swift
//  LLMtest
//
//  Created by Carter Gregg on 6/25/25.
//

import Foundation

struct Config {
    // MARK: - API Configuration
    
    // OpenAI Configuration
    static let openAIAPIKey = "YOUR_OPENAI_API_KEY_HERE"
    static let openAIEndpoint = "https://api.openai.com/v1/chat/completions"
    static let openAIModel = "gpt-3.5-turbo"
    
    // Anthropic Configuration (Claude)
    static let anthropicAPIKey = "YOUR_ANTHROPIC_API_KEY_HERE"
    static let anthropicEndpoint = "https://api.anthropic.com/v1/messages"
    static let anthropicModel = "claude-3-sonnet-20240229"
    
    // Google AI Configuration (Gemini)
    static let googleAIAPIKey = "YOUR_GOOGLE_AI_API_KEY_HERE"
    static let googleAIEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
    
    // MARK: - App Configuration
    static let maxTokens = 1000
    static let temperature = 0.7
    static let maxRetries = 3
    
    // MARK: - Provider Selection
    enum Provider: String, CaseIterable {
        case openAI = "OpenAI (GPT)"
        case anthropic = "Anthropic (Claude)"
        case googleAI = "Google AI (Gemini)"
        
        var apiKey: String {
            switch self {
            case .openAI:
                return Config.openAIAPIKey
            case .anthropic:
                return Config.anthropicAPIKey
            case .googleAI:
                return Config.googleAIAPIKey
            }
        }
        
        var endpoint: String {
            switch self {
            case .openAI:
                return Config.openAIEndpoint
            case .anthropic:
                return Config.anthropicEndpoint
            case .googleAI:
                return Config.googleAIEndpoint
            }
        }
        
        var model: String {
            switch self {
            case .openAI:
                return Config.openAIModel
            case .anthropic:
                return Config.anthropicModel
            case .googleAI:
                return "gemini-pro"
            }
        }
    }
    
    // MARK: - User Defaults Keys
    struct UserDefaultsKeys {
        static let selectedProvider = "selectedProvider"
        static let customAPIKey = "customAPIKey"
        static let customEndpoint = "customEndpoint"
        static let customModel = "customModel"
    }
} 