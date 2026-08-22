/* Fixed-storage Ada bridge for the vendored xxHash v0.8.3 implementation. */
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define XXH_INLINE_ALL
#include "../vendor/xxhash/xxhash.h"

enum flyology_xxhash_kind {
    FLYOLOGY_XXH64 = 0,
    FLYOLOGY_XXH3 = 1,
    FLYOLOGY_XXH128 = 2
};

struct flyology_xxhash_state {
    enum flyology_xxhash_kind kind;
    union {
        XXH64_state_t xxh64;
        XXH3_state_t xxh3;
    } state;
};

size_t flyology_object_storage_xxhash_state_size(void)
{
    return sizeof(struct flyology_xxhash_state);
}

size_t flyology_object_storage_xxhash_state_alignment(void)
{
    return _Alignof(struct flyology_xxhash_state);
}

int flyology_object_storage_xxhash_reset(
    void *storage, size_t storage_size, int kind)
{
    struct flyology_xxhash_state *state;

    if (storage == NULL || storage_size < sizeof(*state) ||
        kind < (int)FLYOLOGY_XXH64 || kind > (int)FLYOLOGY_XXH128) {
        return 0;
    }
    state = (struct flyology_xxhash_state *)storage;
    memset(state, 0, sizeof(*state));
    state->kind = (enum flyology_xxhash_kind)kind;
    if (state->kind == FLYOLOGY_XXH64) {
        return XXH64_reset(&state->state.xxh64, UINT64_C(0)) == XXH_OK;
    }
    return XXH3_64bits_reset(&state->state.xxh3) == XXH_OK;
}

int flyology_object_storage_xxhash_update(
    void *storage, const void *data, size_t length)
{
    struct flyology_xxhash_state *state =
        (struct flyology_xxhash_state *)storage;

    if (state == NULL || (data == NULL && length != 0U)) {
        return 0;
    }
    if (state->kind == FLYOLOGY_XXH64) {
        return XXH64_update(&state->state.xxh64, data, length) == XXH_OK;
    }
    if (state->kind == FLYOLOGY_XXH3) {
        return XXH3_64bits_update(&state->state.xxh3, data, length) == XXH_OK;
    }
    if (state->kind == FLYOLOGY_XXH128) {
        return XXH3_128bits_update(&state->state.xxh3, data, length) == XXH_OK;
    }
    return 0;
}

int flyology_object_storage_xxhash_digest(
    const void *storage, unsigned char *output, size_t output_size)
{
    const struct flyology_xxhash_state *state =
        (const struct flyology_xxhash_state *)storage;

    if (state == NULL || output == NULL) {
        return 0;
    }
    if (state->kind == FLYOLOGY_XXH64 && output_size >= 8U) {
        XXH64_canonical_t canonical;
        XXH64_canonicalFromHash(
            &canonical, XXH64_digest(&state->state.xxh64));
        memcpy(output, canonical.digest, sizeof(canonical.digest));
        return 1;
    }
    if (state->kind == FLYOLOGY_XXH3 && output_size >= 8U) {
        XXH64_canonical_t canonical;
        XXH64_canonicalFromHash(
            &canonical, XXH3_64bits_digest(&state->state.xxh3));
        memcpy(output, canonical.digest, sizeof(canonical.digest));
        return 1;
    }
    if (state->kind == FLYOLOGY_XXH128 && output_size >= 16U) {
        XXH128_canonical_t canonical;
        XXH128_canonicalFromHash(
            &canonical, XXH3_128bits_digest(&state->state.xxh3));
        memcpy(output, canonical.digest, sizeof(canonical.digest));
        return 1;
    }
    return 0;
}
