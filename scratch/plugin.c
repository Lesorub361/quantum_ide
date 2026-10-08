#define WASM_EXPORT __attribute__((visibility("default")))

static unsigned char WASM_MEMORY[65536];
static int next_free = 0;

WASM_EXPORT
void* alloc(int size) {
    if (next_free + size > 65536) {
        next_free = 0;
    }
    void* ptr = &WASM_MEMORY[next_free];
    next_free += size;
    return ptr;
}

WASM_EXPORT
void dealloc(void* ptr, int size) {
    // No-op for simple bump allocator
}

extern void host_log(const char* ptr, int len);

WASM_EXPORT
unsigned long long run_plugin(int action_id, char* ptr, int len) {
    ptr[len] = '\0';
    
    // Log message
    host_log("Input processed by plugin", 25);
    
    char* result = (char*)alloc(len + 1);
    
    if (action_id == 1) {
        // Uppercase
        for (int i = 0; i < len; i++) {
            if (ptr[i] >= 'a' && ptr[i] <= 'z') {
                result[i] = ptr[i] - 32;
            } else {
                result[i] = ptr[i];
            }
        }
    } else if (action_id == 2) {
        // Lowercase
        for (int i = 0; i < len; i++) {
            if (ptr[i] >= 'A' && ptr[i] <= 'Z') {
                result[i] = ptr[i] + 32;
            } else {
                result[i] = ptr[i];
            }
        }
    } else if (action_id == 3) {
        // Reverse
        for (int i = 0; i < len; i++) {
            result[i] = ptr[len - 1 - i];
        }
    } else {
        // Echo
        for (int i = 0; i < len; i++) {
            result[i] = ptr[i];
        }
    }
    result[len] = '\0';
    
    unsigned long long ptr_val = (unsigned long long)(unsigned int)result;
    unsigned long long len_val = (unsigned long long)len;
    
    return (ptr_val << 32) | len_val;
}
