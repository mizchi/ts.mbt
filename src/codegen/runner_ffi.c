#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Write bytes to a temp file and return the path
char* write_temp_wasm(const unsigned char* bytes, int len) {
    char* path = (char*)malloc(256);
    snprintf(path, 256, "/tmp/moonbit_wasm_%d.wasm", getpid());

    FILE* f = fopen(path, "wb");
    if (!f) {
        free(path);
        return NULL;
    }
    fwrite(bytes, 1, len, f);
    fclose(f);
    return path;
}

// Run wasmtime and get result
// Returns the output as a string, or NULL on error
char* run_wasmtime(const char* wasm_path, const char* func_name, double* args, int argc) {
    char cmd[4096];
    char args_str[1024] = "";

    // Build args string
    for (int i = 0; i < argc; i++) {
        char arg[64];
        snprintf(arg, 64, " %.17g", args[i]);
        strcat(args_str, arg);
    }

    // Build command
    snprintf(cmd, 4096, "wasmtime run -W gc --invoke %s %s%s 2>&1",
             func_name, wasm_path, args_str);

    FILE* fp = popen(cmd, "r");
    if (!fp) {
        return NULL;
    }

    // Read all lines and keep the last non-empty line (the result)
    char* result = (char*)malloc(1024);
    char* last_line = (char*)malloc(1024);
    result[0] = '\0';
    last_line[0] = '\0';

    while (fgets(result, 1024, fp) != NULL) {
        // Skip warning lines
        if (strncmp(result, "warning:", 8) != 0) {
            strcpy(last_line, result);
        }
    }

    free(result);

    if (last_line[0] == '\0') {
        free(last_line);
        pclose(fp);
        return NULL;
    }

    // Remove trailing newline
    int len = strlen(last_line);
    if (len > 0 && last_line[len-1] == '\n') {
        last_line[len-1] = '\0';
    }

    pclose(fp);
    return last_line;
}

// Cleanup temp file
void cleanup_temp_wasm(const char* path) {
    if (path) {
        unlink(path);
        free((void*)path);
    }
}

// Free result string
void free_result(char* result) {
    if (result) {
        free(result);
    }
}

// Load a byte from memory
unsigned char moonbit_load_byte(const char* ptr, int offset) {
    return (unsigned char)ptr[offset];
}
