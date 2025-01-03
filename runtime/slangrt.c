
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
    int mark; // for mark and sweep GC
    const int* ref_offsets;
    // void (*destroyer)();
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

SLANG_API slang_int_t rt_str_len(char *txt)
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

SLANG_API char rt_str_get(char *txt, slang_int_t pos)
{
    return std_str_get(txt, pos);
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

SLANG_API slang_int_t std_file_get_stdin()
{
    FILE *f = stdin;
    return (slang_int_t)f;
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

SLANG_API char *std_file_readln(slang_int_t handle)
{
    char *buffer = rt_malloc(300);
    if (handle != 0)
    {
        FILE *f = (FILE *)handle;
        char* s_read = fgets(buffer, 300, f);
        // printf("std_file_readln: '%s'\n", buf2);
        if (!s_read) {
            std_panic("fgets failed!");
        }
    }
    else
    {
        std_panic("Closed file handle");
    }
    return buffer;
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

void *rt_malloc_with_destroyer(size_t size, const int* ref_offsets)
{
    rt_ref_mem_t *ptr = malloc(size + sizeof(rt_ref_mem_t));
    if (((intptr_t)(ptr) & 0x3) != 0) {
        std_panic("Unaligned malloc!");
    }
    ptr->next = g_gc_root;
    g_gc_root = ptr;
    ptr->count = 1;
    ptr->mark = 0;
    ptr->ref_offsets = ref_offsets;
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
        // if (p->destroyer != NULL)
        // {
        //     p->destroyer(ptr);
        // }
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
