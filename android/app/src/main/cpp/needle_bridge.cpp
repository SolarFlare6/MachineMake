#include <ctype.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <algorithm>

#include "needle.h"

#if defined(__aarch64__) || defined(__arm__) || defined(__x86_64__)
#define NEEDLE_SUPPORTED_ABI 1
#else
#define NEEDLE_SUPPORTED_ABI 0
#endif

#if defined(__x86_64__)
// Provide std::__ndk1::__hash_memory for NDK 27 where it is header-inlined
namespace std {
inline namespace __ndk1 {
__attribute__((visibility("hidden"), weak))
size_t __hash_memory(const void* ptr, size_t len) noexcept {
    const uint8_t* p = static_cast<const uint8_t*>(ptr);
    size_t h = 14695981039346656037ULL;
    for (size_t i = 0; i < len; ++i) {
        h ^= static_cast<size_t>(p[i]);
        h *= 1099511628211ULL;
    }
    return h;
}
} // namespace __ndk1
} // namespace std

// Compatibility shims for Linux x86_64 ctype/fscanf symbols when linking on Android Bionic x86_64
extern "C" {

static uint16_t g_ctype_b_table[384];
static int32_t g_ctype_tolower_table[384];
static int32_t g_ctype_toupper_table[384];
static const uint16_t* g_ctype_b_ptr = nullptr;
static const int32_t* g_ctype_tolower_ptr = nullptr;
static const int32_t* g_ctype_toupper_ptr = nullptr;

static void init_ctype_tables(void) {
    if (g_ctype_b_ptr != nullptr) return;
    for (int i = -128; i < 256; ++i) {
        int idx = i + 128;
        unsigned char c = static_cast<unsigned char>(i);
        uint16_t mask = 0;
        if (i >= 0) {
            if (isupper(c))  mask |= (1 << 8);   // _ISupper
            if (islower(c))  mask |= (1 << 9);   // _ISlower
            if (isalpha(c))  mask |= (1 << 10);  // _ISalpha
            if (isdigit(c))  mask |= (1 << 11);  // _ISdigit
            if (isxdigit(c)) mask |= (1 << 12);  // _ISxdigit
            if (isspace(c))  mask |= (1 << 13);  // _ISspace
            if (isprint(c))  mask |= (1 << 14);  // _ISprint
            if (isgraph(c))  mask |= (1 << 15);  // _ISgraph
            if (isblank(c))  mask |= (1 << 0);   // _ISblank
            if (iscntrl(c))  mask |= (1 << 1);   // _IScntrl
            if (ispunct(c))  mask |= (1 << 2);   // _ISpunct
            if (isalnum(c))  mask |= (1 << 3);   // _ISalnum
        }
        g_ctype_b_table[idx] = mask;
        g_ctype_tolower_table[idx] = (i >= 0) ? tolower(c) : i;
        g_ctype_toupper_table[idx] = (i >= 0) ? toupper(c) : i;
    }
    g_ctype_b_ptr = &g_ctype_b_table[128];
    g_ctype_tolower_ptr = &g_ctype_tolower_table[128];
    g_ctype_toupper_ptr = &g_ctype_toupper_table[128];
}

__attribute__((visibility("hidden"))) const uint16_t** __ctype_b_loc(void) {
    init_ctype_tables();
    return &g_ctype_b_ptr;
}

__attribute__((visibility("hidden"))) const int32_t** __ctype_tolower_loc(void) {
    init_ctype_tables();
    return &g_ctype_tolower_ptr;
}

__attribute__((visibility("hidden"))) const int32_t** __ctype_toupper_loc(void) {
    init_ctype_tables();
    return &g_ctype_toupper_ptr;
}

__attribute__((visibility("hidden"))) int __isoc99_fscanf(FILE* stream, const char* format, ...) {
    va_list args;
    va_start(args, format);
    int rc = vfscanf(stream, format, args);
    va_end(args);
    return rc;
}

__attribute__((visibility("hidden"))) int bcmp(const void* s1, const void* s2, size_t n) {
    return memcmp(s1, s2, n);
}

struct machmake_tls_index {
    unsigned long ti_module;
    unsigned long ti_offset;
};

} // extern "C"

#include <pthread.h>
static pthread_key_t g_tls_key;
static pthread_once_t g_tls_once = PTHREAD_ONCE_INIT;

static void make_tls_key(void) {
    pthread_key_create(&g_tls_key, free);
}

extern "C" __attribute__((visibility("hidden"))) void* __tls_get_addr(machmake_tls_index* ti) {
    pthread_once(&g_tls_once, make_tls_key);
    uint8_t* block = static_cast<uint8_t*>(pthread_getspecific(g_tls_key));
    if (!block) {
        block = static_cast<uint8_t*>(calloc(1, 65536));
        if (block) {
            // Initialize 4-byte .tdata initial value (0xffffffff) at offset 0
            *reinterpret_cast<uint32_t*>(block) = 0xFFFFFFFFu;
        }
        pthread_setspecific(g_tls_key, block);
    }
    return block + (ti->ti_offset & 0xFFFF);
}
#endif

static unsigned char* g_mapped_cact = nullptr;
static size_t g_mapped_size = 0;
static char g_loaded_path[1024] = {0};
static int g_is_loaded = 0;
static char g_bridge_error[512] = {0};

extern "C" {

NEEDLE_API void* machmake_needle_alloc(int size) {
    if (size <= 0) return nullptr;
    return calloc(1, static_cast<size_t>(size));
}

NEEDLE_API void machmake_needle_free(void* ptr) {
    if (ptr != nullptr) {
        free(ptr);
    }
}

NEEDLE_API int machmake_needle_is_supported_abi(void) {
    return NEEDLE_SUPPORTED_ABI;
}

NEEDLE_API int machmake_needle_is_loaded(void) {
    return g_is_loaded;
}

NEEDLE_API const char* machmake_needle_last_error(void) {
#if NEEDLE_SUPPORTED_ABI
    if (g_bridge_error[0] != '\0') {
        return g_bridge_error;
    }
    const char* err = needle_last_error();
    return err ? err : "";
#else
    return "Cactus Needle 3 native library is not supported on this CPU architecture.";
#endif
}

NEEDLE_API int machmake_needle_load_file(const char* path) {
#if NEEDLE_SUPPORTED_ABI
    g_bridge_error[0] = '\0';
    if (!path || path[0] == '\0') {
        snprintf(g_bridge_error, sizeof(g_bridge_error), "Model path is empty");
        return -1;
    }

    // If the exact same .cact file is already loaded in Needle, reuse it.
    if (g_is_loaded && g_mapped_cact != nullptr && strcmp(g_loaded_path, path) == 0) {
        return 0;
    }

    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        snprintf(g_bridge_error, sizeof(g_bridge_error), "Failed to open .cact file: %s", path);
        return -2;
    }

    struct stat st;
    if (fstat(fd, &st) < 0 || st.st_size <= 0) {
        close(fd);
        snprintf(g_bridge_error, sizeof(g_bridge_error), "Failed to stat .cact file: %s", path);
        return -3;
    }

    size_t file_size = static_cast<size_t>(st.st_size);
    void* mapped = mmap(nullptr, file_size, PROT_READ, MAP_PRIVATE, fd, 0);
    close(fd);

    if (mapped == MAP_FAILED || mapped == nullptr) {
        snprintf(g_bridge_error, sizeof(g_bridge_error), "mmap failed for .cact file (%zu bytes)", file_size);
        return -4;
    }

    int rc = needle_load(static_cast<const unsigned char*>(mapped), static_cast<unsigned long long>(file_size));
    if (rc < 0) {
        const char* nerr = needle_last_error();
        snprintf(
            g_bridge_error,
            sizeof(g_bridge_error),
            "needle_load failed (rc=%d): %s",
            rc,
            nerr ? nerr : "unknown error"
        );
        munmap(mapped, file_size);
        return rc;
    }

    if (g_mapped_cact != nullptr && g_mapped_size > 0) {
        munmap(g_mapped_cact, g_mapped_size);
    }

    g_mapped_cact = static_cast<unsigned char*>(mapped);
    g_mapped_size = file_size;
    strncpy(g_loaded_path, path, sizeof(g_loaded_path) - 1);
    g_loaded_path[sizeof(g_loaded_path) - 1] = '\0';
    g_is_loaded = 1;
    return rc;
#else
    (void)path;
    return -99;
#endif
}

NEEDLE_API int machmake_needle_init(
    const char* system_prompt,
    const char* tools_json
) {
#if NEEDLE_SUPPORTED_ABI
    g_bridge_error[0] = '\0';
    if (!g_is_loaded) {
        snprintf(g_bridge_error, sizeof(g_bridge_error), "Needle model is not loaded");
        return -1;
    }
    return needle_init(system_prompt, tools_json, nullptr);
#else
    (void)system_prompt;
    (void)tools_json;
    return -99;
#endif
}

NEEDLE_API int machmake_needle_complete(
    const char* input,
    int max_new_tokens,
    char* out,
    int out_capacity
) {
#if NEEDLE_SUPPORTED_ABI
    g_bridge_error[0] = '\0';
    if (!g_is_loaded) {
        snprintf(g_bridge_error, sizeof(g_bridge_error), "Needle model is not loaded");
        return -1;
    }
    return needle_complete(input, nullptr, 0, max_new_tokens, out, out_capacity);
#else
    (void)input;
    (void)max_new_tokens;
    (void)out;
    (void)out_capacity;
    return -99;
#endif
}

NEEDLE_API void machmake_needle_reset(void) {
#if NEEDLE_SUPPORTED_ABI
    if (g_is_loaded) {
        needle_reset();
    }
#endif
}

} // extern "C"
