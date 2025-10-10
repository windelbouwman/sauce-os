#include <execinfo.h>
#include <inttypes.h>
#include <math.h>
#include <setjmp.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <dlfcn.h>
#include <SDL3/SDL.h>

#include "slangrt.h"

extern slang_int_t main2();

int g_argc;
char** g_argv;

#if defined __GNUC__
void std_exit(slang_int_t code) __attribute__((noreturn));
void std_panic(const char* message) __attribute__((noreturn));
#define SLANG_API
#elif defined _MSC_VER
__declspec(noreturn) __declspec(dllexport) void std_exit(slang_int_t code);
__declspec(noreturn) void std_panic(const char* message);
#define SLANG_API __declspec(dllexport)
#else
#error unsupported compiler
#endif

slang_exception_handler_t* g_except_hook;
void* g_except_value;
void* tmp_array_lit;

SLANG_API void std_print(char* message)
{
    puts(message);
}

SLANG_API char* std_read_line(char* prompt)
{
    char* text = rt_malloc_str(300);
    fputs(prompt, stdout);
    char* s_read = fgets(text, 300, stdin);
    if (!s_read) {
        std_panic("fgets failed!");
    }
    return s_read;
}

SLANG_API void std_putc(const char* ch)
{
    // TBD: do we require special char type?
    putchar(ch[0]);
}

void print_trace(void)
{
    // #ifdef UNIX
    void* array[10];
    char** strings;
    int size, i;

    size = backtrace(array, 10);
    strings = backtrace_symbols(array, size);
    if (strings != NULL) {

        printf("Obtained %d stack frames.\n", size);
        for (i = 0; i < size; i++)
            printf("%s\n", strings[i]);
    }

    free(strings);
    // #endif
}

void std_exit(slang_int_t code)
{
    if (code != 0) {
        print_trace();
    }
    exit(code);
}

SLANG_API char std_get_path_separator(void)
{
#if defined(_WIN32)
    return '\\';
#else
    return '/';
#endif
}

void std_panic(const char* message)
{
    puts(message);
    raise(SIGTRAP);
    std_exit(1);
}

char* rt_int_to_str(slang_int_t x)
{
    char buffer[50];
    snprintf(buffer, 50, "%" PRIdPTR, x);
    char* text = rt_malloc_str(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

SLANG_API char* std_float_to_str(slang_float_t x)
{
    char buffer[50];
    snprintf(buffer, 50, "%f", x);
    char* text = rt_malloc_str(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

SLANG_API char* std_float_to_str2(slang_float_t x, slang_int_t digits)
{
    char buffer[50];
    snprintf(buffer, 50, "%.*f", (int)digits, x);
    char* text = rt_malloc_str(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

char* rt_char_to_str(char x)
{
    char* text = rt_malloc_str(2);
    text[0] = x;
    text[1] = 0;
    return text;
}

SLANG_API slang_int_t std_str_len(char* txt)
{
    return strlen(txt);
}

SLANG_API slang_int_t rt_str_len(char* txt)
{
    return std_str_len(txt);
}

SLANG_API slang_int_t std_ord(char c)
{
    return c;
}

SLANG_API char std_chr(slang_int_t val)
{
    return val;
}

SLANG_API char* std_str_slice(char* txt, slang_int_t begin, slang_int_t end)
{
    const int size = end - begin;
    char* buffer = rt_malloc_str(size + 1);
    memcpy(buffer, &txt[begin], size);
    buffer[size] = 0;
    return buffer;
}

// TBD: special case of slice?
SLANG_API char std_str_get(char* txt, slang_int_t pos)
{
    return txt[pos];
}

SLANG_API char rt_str_get(char* txt, slang_int_t pos)
{
    return std_str_get(txt, pos);
}

SLANG_API slang_bool_t std_file_exists(char* filename)
{
    FILE* file = fopen(filename, "r");
    if (file) {
        fclose(file);
        return 1;
    } else {
        return 0;
    }
}

SLANG_API char* std_read_file(char* filename)
{
    char* buffer = 0;
    FILE* f = fopen(filename, "r");
    if (f) {
        fseek(f, 0, SEEK_END);
        int length = ftell(f);
        buffer = rt_malloc_str(length + 1);
        fseek(f, 0, SEEK_SET);
        fread(buffer, 1, length, f);
        buffer[length] = 0;
        fclose(f);
    } else {
        printf("File %s not found!\n", filename);
        std_panic("File not found!");
    }
    return buffer;
}

SLANG_API slang_int_t std_file_get_stdin()
{
    FILE* f = stdin;
    return (slang_int_t)f;
}

SLANG_API slang_int_t std_file_get_stdout()
{
    FILE* f = stdout;
    return (slang_int_t)f;
}

SLANG_API slang_int_t std_file_open(char* filename, char* mode)
{
    FILE* f = fopen(filename, mode);
    if (!f) {
        printf("Error opening file: [%s] with mode [%s]\n", filename, mode);
        std_panic("std_file_open: Cannot open file");
    }
    return (slang_int_t)f;
}

SLANG_API char* std_file_readln(slang_int_t handle)
{
    char* buffer = rt_malloc_str(300);
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        char* s_read = fgets(buffer, 300, f);
        // printf("std_file_readln: '%s'\n", buf2);
        if (!s_read) {
            std_panic("fgets failed!");
        }
    } else {
        std_panic("Closed file handle");
    }
    return buffer;
}

SLANG_API void std_file_writeln(slang_int_t handle, char* line)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        fprintf(f, "%s\n", line);
    }
}

SLANG_API void std_file_write(slang_int_t handle, char* text)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        fputs(text, f);
    }
}

SLANG_API slang_int_t std_file_read_n_bytes(slang_int_t handle, uint8_t* buffer,
                                            slang_int_t bufsize)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        return fread(buffer, 1, bufsize, f);
    } else {
        std_panic("std_file_read_n_bytes: invalid file");
    }
}

SLANG_API slang_int_t std_file_write_n_bytes(slang_int_t handle,
                                             uint8_t* buffer,
                                             slang_int_t bufsize)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        return fwrite(buffer, 1, bufsize, f);
    } else {
        std_panic("std_file_write_n_bytes: invalid file");
    }
}

SLANG_API void std_file_seek(slang_int_t handle, slang_int_t pos)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        int res = fseek(f, pos, SEEK_SET);
        if (res != 0) {
            std_panic("std_file_seek: fseek failed");
        }
    } else {
        std_panic("std_file_seek: invalid file");
    }
}

SLANG_API slang_int_t std_file_tell(slang_int_t handle)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        int res = ftell(f);
        if (res < 0) {
            std_panic("std_file_tell: ftell failed");
        }
        return res;
    } else {
        std_panic("std_file_tell: invalid file");
    }
}

SLANG_API void std_file_close(slang_int_t handle)
{
    if (handle != 0) {
        FILE* f = (FILE*)handle;
        fclose(f);
    }
}

void* slangrt_box_char(char value)
{
    intptr_t p2 = value;
    p2 = (p2 << 1) | 1;
    return (void*)p2;
}

char slangrt_unbox_char(void* p1)
{
    intptr_t p2 = (intptr_t)p1;
    p2 = p2 >> 1;
    return (char)p2;
}

void* slangrt_box_bool(slang_bool_t value)
{
    intptr_t p2 = (intptr_t)value;
    p2 = (p2 << 1) | 1;
    return (void*)p2;
}

slang_bool_t slangrt_unbox_bool(void* p1)
{
    intptr_t p2 = (intptr_t)p1;
    p2 = p2 >> 1;
    return (slang_bool_t)p2;
}

void* slangrt_box_int64(slang_int64_t value)
{
    intptr_t p2 = value;
    // TODO: we loose 1 bit here!
    // IDEA: alloc 8 bytes on the heap
    p2 = (p2 << 1) | 1;
    return (void*)p2;
}

slang_int64_t slangrt_unbox_int64(void* p1)
{
    intptr_t p2 = (intptr_t)p1;
    p2 = p2 >> 1;
    return (slang_int64_t)p2;
}

void* slangrt_box_uint8(slang_uint8_t value)
{
    uintptr_t p2 = value;
    p2 = (p2 << 1) | 1;
    return (void*)p2;
}

slang_uint8_t slangrt_unbox_uint8(void* p1)
{
    uintptr_t p2 = (uintptr_t)p1;
    p2 = p2 >> 1;
    return (slang_uint8_t)p2;
}

void* slangrt_box_float64(slang_float64_t value)
{
    void* p1 = rt_malloc(sizeof(slang_float64_t));
    slang_float64_t* p2 = p1;
    *p2 = value;
    return p1;
}

slang_float64_t slangrt_unbox_float64(void* p1)
{
    slang_float64_t* p2 = p1;
    return *p2;
}

int main(int argc, char** argv)
{
    g_argc = argc;
    g_argv = argv;
    rt_gc_init(&argc);
    int res = main2();
    rt_gc_finalize();
    return res;
}

SLANG_API slang_int_t std_get_n_args(void)
{
    return g_argc - 1;
}

SLANG_API char* std_get_arg(slang_int_t index)
{
    return rt_str_new(g_argv[index + 1]);
}

SLANG_API slang_int_t std_get_time(void)
{
    clock_t now = clock();
    // Time in nano seconds
    return now * (1000000000 / CLOCKS_PER_SEC);
}

// Create a string on the heap..
SLANG_API char* rt_str_new(const char* a)
{
    char* buffer = rt_malloc_str(strlen(a) + 2);
    strcpy(buffer, a);
    return buffer;
}

char* rt_str_concat(char* a, char* b)
{
    char* buffer = rt_malloc_str(strlen(a) + strlen(b) + 2);
    strcpy(buffer, a);
    strcat(buffer, b);
    return buffer;
}

int rt_str_compare(char* a, char* b)
{
    int res = (strcmp(a, b) == 0) ? 1 : 0;
    return res;
}

