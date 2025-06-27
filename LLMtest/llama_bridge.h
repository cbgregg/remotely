#ifndef LLAMA_BRIDGE_H
#define LLAMA_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Simple bridge function declaration
const char* run_llama(const char* model_path, const char* prompt);

#ifdef __cplusplus
}
#endif

#endif /* LLAMA_BRIDGE_H */ 