import Foundation

class LlamaWrapper {
    static let shared = LlamaWrapper()
    private init() {}

    func runInference(prompt: String, modelPath: String) -> String {
        // Real llama.cpp implementation for both macOS and iOS
        guard let cResult = run_llama(modelPath, prompt) else {
            return "Error: Failed to run inference"
        }
        
        let result = String(cString: cResult)
        free(UnsafeMutableRawPointer(mutating: cResult))
        return result
    }
} 