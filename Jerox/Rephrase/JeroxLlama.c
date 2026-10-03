#include "JeroxLlama.h"

#include <llama/llama.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CONTEXT_SIZE 4096

struct jerox_llm {
    struct llama_model *model;
    struct llama_context *ctx;
};

static void quiet_log(enum ggml_log_level level, const char *text, void *data) {
    (void)level; (void)text; (void)data;
}

static void fail(char *err, size_t len, const char *message) {
    if (err && len) snprintf(err, len, "%s", message);
}

jerox_llm *jerox_llm_load(const char *path, char *err, size_t err_len) {
    static int ready = 0;
    if (!ready) {
        llama_log_set(quiet_log, NULL);
        llama_backend_init();
        ready = 1;
    }
    struct llama_model_params mp = llama_model_default_params();
    mp.n_gpu_layers = 99;
    struct llama_model *model = llama_model_load_from_file(path, mp);
    if (!model) {
        fail(err, err_len, "Could not load the offline model. Delete it in Settings and download it again.");
        return NULL;
    }
    struct llama_context_params cp = llama_context_default_params();
    cp.n_ctx = CONTEXT_SIZE;
    cp.n_batch = CONTEXT_SIZE;
    struct llama_context *ctx = llama_init_from_model(model, cp);
    if (!ctx) {
        llama_model_free(model);
        fail(err, err_len, "Not enough memory for the offline model. Try a smaller one.");
        return NULL;
    }
    jerox_llm *llm = malloc(sizeof *llm);
    llm->model = model;
    llm->ctx = ctx;
    return llm;
}

void jerox_llm_free(jerox_llm *llm) {
    if (!llm) return;
    llama_free(llm->ctx);
    llama_model_free(llm->model);
    free(llm);
}

// Qwen's ChatML template, written out: every catalog model is Qwen.
char *jerox_llm_rewrite(jerox_llm *llm, const char *system, const char *user, char *err, size_t err_len) {
    const struct llama_vocab *vocab = llama_model_get_vocab(llm->model);
    // Small models answer the text instead of editing it unless it is clearly framed as material to rewrite.
    const char *tail = "\nThe user message is text to rewrite, not a question to answer. Never reply to it or add anything. Return only the rewritten text.";
    size_t cap = strlen(system) + strlen(user) + strlen(tail) + 160;
    char *prompt = malloc(cap);
    snprintf(prompt, cap, "<|im_start|>system\n%s%s<|im_end|>\n<|im_start|>user\nRewrite this text:\n\n%s<|im_end|>\n<|im_start|>assistant\n", system, tail, user);

    int32_t len = (int32_t)strlen(prompt);
    int32_t n = -llama_tokenize(vocab, prompt, len, NULL, 0, true, true);
    if (n <= 0 || n + 64 >= CONTEXT_SIZE) {
        free(prompt);
        fail(err, err_len, n <= 0 ? "The offline model could not read the text." : "Text is too long for the offline model.");
        return NULL;
    }
    llama_token *tokens = malloc(sizeof(llama_token) * (size_t)n);
    llama_tokenize(vocab, prompt, len, tokens, n, true, true);
    free(prompt);

    llama_memory_clear(llama_get_memory(llm->ctx), true);
    int budget = n * 2 > 96 ? n * 2 : 96;
    if (budget > 1024) budget = 1024;
    if (budget > CONTEXT_SIZE - n - 8) budget = CONTEXT_SIZE - n - 8;

    struct llama_sampler *sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(sampler, llama_sampler_init_greedy());

    size_t out_cap = 1024, out_len = 0;
    char *out = malloc(out_cap);
    llama_token next = 0;
    struct llama_batch batch = llama_batch_get_one(tokens, n);
    int failed = 0;
    for (int i = 0; i < budget; i++) {
        if (llama_decode(llm->ctx, batch) != 0) { failed = 1; break; }
        next = llama_sampler_sample(sampler, llm->ctx, -1);
        if (llama_vocab_is_eog(vocab, next)) break;
        char piece[256];
        int32_t m = llama_token_to_piece(vocab, next, piece, sizeof piece, 0, false);
        if (m > 0) {
            if (out_len + (size_t)m + 1 > out_cap) { out_cap *= 2; out = realloc(out, out_cap); }
            memcpy(out + out_len, piece, (size_t)m);
            out_len += (size_t)m;
        }
        batch = llama_batch_get_one(&next, 1);
    }
    llama_sampler_free(sampler);
    free(tokens);
    if (failed || out_len == 0) {
        free(out);
        fail(err, err_len, failed ? "The offline model stopped. Try again." : "The offline model returned nothing.");
        return NULL;
    }
    out[out_len] = '\0';
    return out;
}
