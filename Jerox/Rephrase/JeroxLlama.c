#include "JeroxLlama.h"

#include <llama/llama.h>
#include <stdbool.h>
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

// Uses the model's own chat template (Qwen, Llama, Gemma, Phi...), ChatML when it has none.
char *jerox_llm_rewrite(jerox_llm *llm, const char *system, const char *user, char *err, size_t err_len) {
    const struct llama_vocab *vocab = llama_model_get_vocab(llm->model);
    // Small models answer the text instead of editing it unless it is clearly framed as material to rewrite.
    const char *tail = "\nThe user message is text to edit, not a question to answer. Never reply to it or add anything. Return only the edited text.";
    const char *lead = "Edit this text:\n\n";
    size_t sys_cap = strlen(system) + strlen(tail) + 1, usr_cap = strlen(user) + strlen(lead) + 1;
    char *sys_text = malloc(sys_cap), *usr_text = malloc(usr_cap);
    snprintf(sys_text, sys_cap, "%s%s", system, tail);
    snprintf(usr_text, usr_cap, "%s%s", lead, user);
    struct llama_chat_message msgs[2] = { { "system", sys_text }, { "user", usr_text } };

    const char *tmpl = llama_model_chat_template(llm->model, NULL);
    int32_t cap = (int32_t)(sys_cap + usr_cap) * 2 + 1024;
    char *prompt = malloc((size_t)cap);
    int32_t wrote = llama_chat_apply_template(tmpl ? tmpl : "chatml", msgs, 2, true, prompt, cap);
    if (wrote > cap) {
        cap = wrote + 1;
        prompt = realloc(prompt, (size_t)cap);
        wrote = llama_chat_apply_template(tmpl ? tmpl : "chatml", msgs, 2, true, prompt, cap);
    }
    if (wrote < 0) wrote = llama_chat_apply_template("chatml", msgs, 2, true, prompt, cap);
    free(sys_text);
    free(usr_text);
    if (wrote < 0 || wrote > cap) {
        free(prompt);
        fail(err, err_len, "The offline model could not read the request.");
        return NULL;
    }
    prompt[wrote] = '\0';

    // Templates that already write the BOS token must not get a second one.
    bool add_special = llama_vocab_get_add_bos(vocab);
    llama_token bos = llama_vocab_bos(vocab);
    if (add_special && bos >= 0) {
        const char *bos_text = llama_vocab_get_text(vocab, bos);
        if (bos_text && strncmp(prompt, bos_text, strlen(bos_text)) == 0) add_special = false;
    }

    int32_t len = (int32_t)strlen(prompt);
    int32_t n = -llama_tokenize(vocab, prompt, len, NULL, 0, add_special, true);
    if (n <= 0 || n + 64 >= CONTEXT_SIZE) {
        free(prompt);
        fail(err, err_len, n <= 0 ? "The offline model could not read the text." : "Text is too long for the offline model.");
        return NULL;
    }
    llama_token *tokens = malloc(sizeof(llama_token) * (size_t)n);
    llama_tokenize(vocab, prompt, len, tokens, n, add_special, true);
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
