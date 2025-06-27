#include "llama_bridge.h"

// Real llama.cpp implementation for both macOS and iOS
#include "llama/llama.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Model-specific configurations
typedef struct {
    int context_size;
    int batch_size;
    float temperature;
    int top_k;
    float top_p;
    int max_tokens;
} model_config_t;

// Detect model type from filename and configure accordingly
model_config_t get_model_config(const char* model_path) {
    model_config_t config;
    
    if (strstr(model_path, "phi-3") || strstr(model_path, "Phi-3")) {
        // Phi-3 Mini configuration - iOS OPTIMIZED
        config.context_size = 256;  // Very small context for iOS
        config.batch_size = 32;     // Small batch size for iOS
        config.temperature = 0.1f;  // Conservative for accuracy
        config.top_k = 3;           // Small pool
        config.top_p = 0.2f;        // Conservative sampling
        config.max_tokens = 30;     // Short responses for iOS
    } else if (strstr(model_path, "tinyllama") || strstr(model_path, "TinyLlama")) {
        // TinyLlama configuration - iOS OPTIMIZED
        config.context_size = 256;  // Very small context for iOS
        config.batch_size = 32;     // Small batch size for iOS
        config.temperature = 0.1f;  // Conservative for accuracy
        config.top_k = 3;           // Small pool
        config.top_p = 0.2f;        // Conservative sampling
        config.max_tokens = 30;     // Short responses for iOS
    } else {
        // Default configuration - iOS OPTIMIZED
        config.context_size = 256;  // Very small context for iOS
        config.batch_size = 32;     // Small batch size for iOS
        config.temperature = 0.7f;
        config.top_k = 40;
        config.top_p = 0.9f;
        config.max_tokens = 50;     // Moderate length for iOS
    }
    
    return config;
}

const char* run_llama(const char* model_path, const char* prompt) {
    // Initialize backend
    llama_backend_init();
    
    // Check if model file exists and is readable
    FILE* test_file = fopen(model_path, "rb");
    if (!test_file) {
        llama_backend_free();
        return strdup("Error: Model file not found. Please download the model first.");
    }
    
    // Check file size (should be at least 1MB for a valid model)
    fseek(test_file, 0, SEEK_END);
    long file_size = ftell(test_file);
    fseek(test_file, 0, SEEK_SET);
    
    if (file_size < 1000000) { // Less than 1MB
        fclose(test_file);
        llama_backend_free();
        return strdup("Error: Model file appears to be corrupted or incomplete. Please re-download the model.");
    }
    
    // Check GGUF magic header
    char header[4];
    size_t read_bytes = fread(header, 1, 4, test_file);
    fclose(test_file);
    
    if (read_bytes != 4 || memcmp(header, "GGUF", 4) != 0) {
        llama_backend_free();
        return strdup("Error: Invalid model file format. Please ensure you have downloaded a valid GGUF model file.");
    }
    
    // Get model-specific configuration
    model_config_t config = get_model_config(model_path);
    
    // Load model with iOS-optimized settings
    struct llama_model_params model_params = llama_model_default_params();
    model_params.use_mmap = false; // Disable mmap on iOS for better compatibility
    model_params.n_gpu_layers = 0; // Force CPU-only on iOS for stability
    
    struct llama_model* model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        llama_backend_free();
        return strdup("Error: Failed to load model. The file may be corrupted or incompatible with this version of the app.");
    }

    // Context settings based on model - iOS optimized
    struct llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = config.context_size;
    ctx_params.n_batch = config.batch_size;
    ctx_params.n_threads = 2; // Fewer threads for iOS
    ctx_params.flash_attn = false; // Disable flash attention for iOS compatibility
    
    struct llama_context* ctx = llama_init_from_model(model, ctx_params);
    if (!ctx) {
        llama_model_free(model);
        llama_backend_free();
        return strdup("Error: Failed to create context");
    }

    // Get vocab
    const struct llama_vocab* vocab = llama_model_get_vocab(model);
    if (!vocab) {
        llama_free(ctx);
        llama_model_free(model);
        llama_backend_free();
        return strdup("Error: Failed to get vocabulary");
    }
    
    // Use the provided prompt as-is (it's already formatted by Swift)
    const char* full_prompt = prompt;
    
    // Tokenize with dynamic buffer size based on model
    const int max_prompt_tokens = config.context_size - config.max_tokens - 50; // Leave room for response
    llama_token* tokens = malloc(max_prompt_tokens * sizeof(llama_token));
    int n_tokens = llama_tokenize(vocab, full_prompt, strlen(full_prompt), tokens, max_prompt_tokens, true, false);
    
    if (n_tokens < 0) {
        free(tokens);
        llama_free(ctx);
        llama_model_free(model);
        llama_backend_free();
        return strdup("Conversation too long. Please start a new chat to continue.");
    }
    
    // Additional safety check
    if (n_tokens > max_prompt_tokens * 0.9) { // If using more than 90% of available tokens
        free(tokens);
        llama_free(ctx);
        llama_model_free(model);
        llama_backend_free();
        return strdup("Context nearly full. Please start a new conversation for better responses.");
    }

    // Process prompt
    struct llama_batch batch = llama_batch_get_one(tokens, n_tokens);
    if (llama_decode(ctx, batch) != 0) {
        llama_free(ctx);
        llama_model_free(model);
        llama_backend_free();
        return strdup("Error: Failed to process prompt");
    }

    // Model-adaptive sampling
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler* sampler = llama_sampler_chain_init(sparams);
    
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(config.top_k));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(config.top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(config.temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(42));

    // Generate response
    char* response = malloc(8192); // Larger buffer for better models
    response[0] = '\0';
    int response_len = 0;
    int tokens_generated = 0;

    while (tokens_generated < config.max_tokens) {
        // Sample next token
        llama_token new_token = llama_sampler_sample(sampler, ctx, -1);
        
        // Check for end of generation
        if (llama_vocab_is_eog(vocab, new_token)) {
            break;
        }

        // Accept the token
        llama_sampler_accept(sampler, new_token);

        // Convert token to text
        char token_text[128];
        int token_len = llama_token_to_piece(vocab, new_token, token_text, sizeof(token_text) - 1, 0, false);
        if (token_len < 0) {
            break;
        }
        token_text[token_len] = '\0';

        // Stop at proper end tokens (model-specific)
        if (strstr(token_text, "<|im_end|>") || strstr(token_text, "<|end|>") || 
            strstr(token_text, "<|im_start|>") || strstr(token_text, "<|system|>") ||
            strstr(token_text, "<|user|>") || strstr(token_text, "<|assistant|>")) {
            break;
        }

        // Add to response
        if (response_len + token_len < 8190) {
            strcat(response, token_text);
            response_len += token_len;
        } else {
            break;
        }

        // Prepare next batch
        struct llama_batch next_batch = llama_batch_get_one(&new_token, 1);
        if (llama_decode(ctx, next_batch) != 0) {
            break;
        }

        tokens_generated++;
        
        // Intelligent stopping conditions
        if (response_len > 50) {
            // For Phi-3, allow longer responses but stop at natural boundaries
            int min_tokens = strstr(model_path, "phi-3") ? 30 : 20;
            
            // Stop at sentence boundaries
            if ((strstr(token_text, ". ") || strstr(token_text, ".\n") || 
                 strstr(token_text, "! ") || strstr(token_text, "?\n") ||
                 strstr(token_text, ".\"") || strstr(token_text, "!\"") || strstr(token_text, "?\"")) && 
                tokens_generated > min_tokens) {
                break;
            }
            
            // Stop if we're starting to repeat or go off-topic
            if (tokens_generated > (config.max_tokens * 0.8) && 
                (strstr(token_text, "\n\n") || strstr(token_text, "  "))) {
                break;
            }
        }
    }

    // Clean up
    llama_sampler_free(sampler);
    free(tokens);
    llama_free(ctx);
    llama_model_free(model);
    llama_backend_free();

    // Enhanced response cleaning
    if (strlen(response) > 0) {
        // Remove any remaining special tokens
        char* pos;
        const char* special_tokens[] = {"<|im_end|>", "<|end|>", "<|im_start|>", 
                                      "<|system|>", "<|user|>", "<|assistant|>", NULL};
        
        for (int i = 0; special_tokens[i] != NULL; i++) {
            while ((pos = strstr(response, special_tokens[i])) != NULL) {
                memmove(pos, pos + strlen(special_tokens[i]), 
                       strlen(pos + strlen(special_tokens[i])) + 1);
            }
        }
        
        // Trim whitespace and newlines
        char* start = response;
        while (*start == ' ' || *start == '\n' || *start == '\t' || *start == '\r') start++;
        
        char* end = start + strlen(start) - 1;
        while (end > start && (*end == ' ' || *end == '\n' || *end == '\t' || *end == '\r')) end--;
        *(end + 1) = '\0';
        
        if (start != response) {
            memmove(response, start, strlen(start) + 1);
        }
        
        // Remove duplicate spaces and clean formatting
        char* cleaned = malloc(strlen(response) + 1);
        int cleaned_idx = 0;
        int space_count = 0;
        
        for (int i = 0; response[i]; i++) {
            if (response[i] == ' ') {
                space_count++;
                if (space_count == 1) {
                    cleaned[cleaned_idx++] = response[i];
                }
            } else {
                space_count = 0;
                cleaned[cleaned_idx++] = response[i];
            }
        }
        cleaned[cleaned_idx] = '\0';
        
        free(response);
        response = cleaned;
        
        // Quality checks
        if (strlen(response) < 3) {
            free(response);
            return strdup("I'm not sure how to respond to that. Could you rephrase your question?");
        }
        
        // Ensure proper sentence ending for longer responses
        if (strlen(response) > 20) {
            char last_char = response[strlen(response) - 1];
            if (last_char != '.' && last_char != '!' && last_char != '?' && 
                last_char != '"' && last_char != '\n') {
                // Only add period if response seems like a statement
                if (strlen(response) < 8180 && !strchr(response, ':') && 
                    strncmp(response + strlen(response) - 3, "...", 3) != 0) {
                    strcat(response, ".");
                }
            }
        }
    }

    if (strlen(response) == 0) {
        free(response);
        return strdup("I'm having trouble generating a response right now.");
    }
    
    return response;
}