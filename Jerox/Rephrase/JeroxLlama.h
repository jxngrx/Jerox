#ifndef JeroxLlama_h
#define JeroxLlama_h

#include <stddef.h>

// llama.cpp lives behind this plain C interface so Swift never imports the `llama` module,
// whose ggml headers clash with the `whisper` module's.
typedef struct jerox_llm jerox_llm;

jerox_llm *jerox_llm_load(const char *path, char *err, size_t err_len);
// Returns a malloc'd UTF-8 string (caller frees), or NULL with `err` filled in.
char *jerox_llm_rewrite(jerox_llm *llm, const char *system, const char *user, char *err, size_t err_len);
void jerox_llm_free(jerox_llm *llm);

#endif
