
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <math.h>
#include <setjmp.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>

#include "slangrt.h"

// Config:
// #define DEBUG_REFCOUNTING

typedef struct rt_ref_mem_tag rt_ref_mem_t;
struct rt_ref_mem_tag
{
    int count;
    void (*destroyer)();
    rt_ref_mem_t* next;
};

extern slang_int_t main2();

rt_ref_mem_t* g_gc_root = NULL;


#if defined __GNUC__
void std_exit(slang_int_t code) __attribute__((noreturn));
void std_panic(const char *message) __attribute__((noreturn));
#define SLANG_API
#elif defined _MSC_VER
__declspec(noreturn) __declspec(dllexport) void std_exit(slang_int_t code);
__declspec(noreturn) void std_panic(const char *message);
#define SLANG_API __declspec(dllexport)
#else
#error unsupported compiler
#endif

slang_exception_handler_t *g_except_hook;
void *g_except_value;

SLANG_API slang_float_t math_powf(slang_float_t a, slang_float_t b)
{
    return powf(a, b);
}

SLANG_API slang_float_t math_log10(slang_float_t value)
{
    return log10(value);
}

SLANG_API slang_float_t math_log2(slang_float_t value)
{
    return log2(value);
}

// slang_float_t math_floor(slang_float_t value)
// {
//     return floor(value);
// }

SLANG_API slang_float_t math_ceil(slang_float_t value)
{
    return ceil(value);
}

SLANG_API void std_print(char *message)
{
    puts(message);
    rt_decref(message);
}

SLANG_API char* std_read_line(char *prompt)
{
    char *text = rt_malloc(300);
    fputs(prompt, stdout);
    char* s_read = fgets(text, 300, stdin);
    if (!s_read) {
        std_panic("fgets failed!");
    }
    return s_read;
}

SLANG_API void std_putc(const char *ch)
{
    // TBD: do we require special char type?
    putchar(ch[0]);
}

void std_exit(slang_int_t code)
{
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

void std_panic(const char *message)
{
    puts(message);
    raise(SIGTRAP);
    std_exit(1);
}

SLANG_API slang_int_t std_str_to_int(char *x)
{
    slang_int_t value = strtoll(x, NULL, 10);
    rt_decref(x);
    return value;
}

char *rt_int_to_str(slang_int_t x)
{
    char buffer[50];
    snprintf(buffer, 50, "%" PRIdPTR, x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

SLANG_API char *std_float_to_str(slang_float_t x)
{
    char buffer[50];
    snprintf(buffer, 50, "%f", x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

SLANG_API char *std_float_to_str2(slang_float_t x, slang_int_t digits)
{
    char buffer[50];
    snprintf(buffer, 50, "%.*f", (int)digits, x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

SLANG_API slang_float_t std_str_to_float(char *x)
{
    double value = strtod(x, NULL);
    return value;
}

char *rt_char_to_str(char x)
{
    char *text = rt_malloc(2);
    text[0] = x;
    text[1] = 0;
    return text;
}

SLANG_API slang_int_t std_str_len(char *txt)
{
    const int len = strlen(txt);
    rt_decref(txt);
    return len;
}

SLANG_API slang_int_t std_ord(char c)
{
    return c;
}

SLANG_API char std_chr(slang_int_t val)
{
    return val;
}

SLANG_API char *std_str_slice(char *txt, slang_int_t begin, slang_int_t end)
{
    const int size = end - begin;
    char *buffer = rt_malloc(size + 1);
    memcpy(buffer, &txt[begin], size);
    rt_decref(txt);
    buffer[size] = 0;
    return buffer;
}

// TBD: special case of slice?
SLANG_API char std_str_get(char *txt, slang_int_t pos)
{
    return txt[pos];
}

SLANG_API char *std_read_file(char *filename)
{
    char *buffer = 0;
    FILE *f = fopen(filename, "r");
    if (f)
    {
        fseek(f, 0, SEEK_END);
        int length = ftell(f);
        buffer = rt_malloc(length + 1);
        fseek(f, 0, SEEK_SET);
        fread(buffer, 1, length, f);
        buffer[length] = 0;
        fclose(f);
    }
    else
    {
        printf("File %s not found!\n", filename);
        std_panic("File not found!");
    }
    rt_decref(filename);
    return buffer;
}

SLANG_API slang_int_t std_file_open(char *filename, char *mode)
{
    FILE *f = fopen(filename, mode);
    if (!f)
    {
        printf("Error opening file: [%s] with mode [%s]\n", filename, mode);
        std_panic("std_file_open: Cannot open file");
    }
    return (slang_int_t)f;
}

SLANG_API void std_file_writeln(slang_int_t handle, char *line)
{
    if (handle != 0)
    {
        FILE *f = (FILE *)handle;
        fprintf(f, "%s\n", line);
    }
}

SLANG_API slang_int_t std_file_read_n_bytes(slang_int_t handle, uint8_t *buffer, slang_int_t bufsize)
{
    if (handle != 0)
    {
        FILE *f = (FILE *)handle;
        return fread(buffer, 1, bufsize, f);
    }
    else
    {
        std_panic("std_file_read_n_bytes: invalid file");
    }
}

SLANG_API slang_int_t std_file_write_n_bytes(slang_int_t handle, uint8_t *buffer, slang_int_t bufsize)
{
    if (handle != 0)
    {
        FILE *f = (FILE *)handle;
        return fwrite(buffer, 1, bufsize, f);
    }
    else
    {
        std_panic("std_file_write_n_bytes: invalid file");
    }
}

SLANG_API void std_file_close(slang_int_t handle)
{
    if (handle != 0)
    {
        FILE *f = (FILE *)handle;
        fclose(f);
    }
}

int g_argc;
char **g_argv;

int main(int argc, char **argv)
{
    g_argc = argc;
    g_argv = argv;
    int res = main2();

    // Cleanup malloc stuff:
    int total = 0, bad = 0;
    rt_ref_mem_t *ptr = g_gc_root;
    rt_ref_mem_t *prev_ptr = NULL;
    while (ptr != NULL) {
        total += 1;
        if (ptr->count > 0) {
            // printf("Count = %d\n", ptr->count);
            bad += 1;
        }
        prev_ptr = ptr;
        ptr = ptr->next;
        free(prev_ptr);
    }
    if (bad > 0) {
        // printf("Total = %d bad = %d\n", total, bad);
        // return 2;
    }

    return res;
}

SLANG_API slang_int_t std_get_n_args(void)
{
    return g_argc - 1;
}

SLANG_API char *std_get_arg(slang_int_t index)
{
    return rt_str_new(g_argv[index + 1]);
}

// Create a string on the heap..
SLANG_API char *rt_str_new(const char *a)
{
    char *buffer = rt_malloc(strlen(a) + 2);
    strcpy(buffer, a);
    return buffer;
}

char *rt_str_concat(char *a, char *b)
{
    char *buffer = rt_malloc(strlen(a) + strlen(b) + 2);
    strcpy(buffer, a);
    strcat(buffer, b);
    rt_decref(a);
    rt_decref(b);
    return buffer;
}

int rt_str_compare(char *a, char *b)
{
    int res = (strcmp(a, b) == 0) ? 1 : 0;
    rt_decref(a);
    rt_decref(b);
    return res;
}

void *rt_malloc(size_t size)
{
    return rt_malloc_with_destroyer(size, NULL);
}

void *rt_malloc_with_destroyer(size_t size, void (*destroyer)(void*))
{
    rt_ref_mem_t *ptr = malloc(size + sizeof(rt_ref_mem_t));
    if (((intptr_t)(ptr) & 0x3) != 0) {
        std_panic("Unaligned malloc!");
    }
    ptr->next = g_gc_root;
    g_gc_root = ptr;
    ptr->count = 1;
    ptr->destroyer = destroyer;
    void *p = (ptr + 1);
    return p;
}

// IDEA: use reference counting to free values.
void rt_incref(void *ptr)
{
    return;

    if (ptr == NULL)
    {
        return;
    }

    rt_ref_mem_t *p = ptr;
    p -= 1;
    if (p->count <= 0) {
        std_panic("rt_incref: Logic error inc-ref on released item!\n");
    }
    p->count += 1;
#ifdef DEBUG_REFCOUNTING
    printf("INCREF New ref count: %d\n", p->count);
#endif
}

void rt_decref(void *ptr)
{
    return;

    if (ptr == NULL)
    {
        return;
    }

    rt_ref_mem_t *p = ptr;
    p -= 1;

    if (p->count <= 0) {
        std_panic("rt_decref: Logic error, dec ref on released item!\n");
    }

    p->count -= 1;

    if (p->count == 0) {
        if (p->destroyer != NULL)
        {
            p->destroyer(ptr);
        }
    }

#ifdef DEBUG_REFCOUNTING
    printf("DECREF New ref count: %d\n", p->count);
#endif
    if (p->count == 0)
    {
        // comment out below, to have malloc only!
        // printf("FREE 0x%X!\n", ptr);
        // free(p);
    }
}
