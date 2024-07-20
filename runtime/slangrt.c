
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <setjmp.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>

// Config:
// #define DEBUG_REFCOUNTING

typedef intptr_t slang_int_t;
typedef double slang_float_t;
extern slang_int_t main2();
void *rt_malloc(int size);
void rt_incref(void *ptr);
void rt_decref(void *ptr);
void std_exit(slang_int_t code) __attribute__((noreturn));
void std_panic(const char *message) __attribute__((noreturn));

struct slang_exception_handler;
typedef struct slang_exception_handler
{
    jmp_buf buf;
    struct slang_exception_handler *prev;
} slang_exception_handler_t;
slang_exception_handler_t *g_except_hook;
void *g_except_value;

slang_float_t math_powf(slang_float_t a, slang_float_t b)
{
    return powf(a, b);
}

slang_float_t math_log10(slang_float_t value)
{
    return log10(value);
}

slang_float_t math_log2(slang_float_t value)
{
    return log2(value);
}

// slang_float_t math_floor(slang_float_t value)
// {
//     return floor(value);
// }

slang_float_t math_ceil(slang_float_t value)
{
    return ceil(value);
}

void std_print(char *message)
{
    puts(message);
    rt_decref(message);
}

char* std_read_line(char *prompt)
{
    char *text = rt_malloc(300);
    fputs(prompt, stdout);
    char* s_read = fgets(text, 300, stdin);
    if (!s_read) {
        std_panic("fgets failed!");
    }
    return s_read;
}

void std_putc(const char *ch)
{
    // TBD: do we require special char type?
    putchar(ch[0]);
}

void std_exit(slang_int_t code)
{
    exit(code);
}


void std_panic(const char *message)
{
    puts(message);
    std_exit(1);
}

slang_int_t std_str_to_int(char *x)
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

char *std_float_to_str(slang_float_t x)
{
    char buffer[50];
    snprintf(buffer, 50, "%f", x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

char *std_float_to_str2(slang_float_t x, slang_int_t digits)
{
    char buffer[50];
    snprintf(buffer, 50, "%.*f", (int)digits, x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

slang_float_t std_str_to_float(char *x)
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

slang_int_t std_str_len(char *txt)
{
    const int len = strlen(txt);
    rt_decref(txt);
    return len;
}

slang_int_t std_ord(char c)
{
    return c;
}

char std_chr(slang_int_t val)
{
    return val;
}

char *std_str_slice(char *txt, slang_int_t begin, slang_int_t end)
{
    const int size = end - begin;
    char *buffer = rt_malloc(size + 1);
    memcpy(buffer, &txt[begin], size);
    rt_decref(txt);
    buffer[size] = 0;
    return buffer;
}

// TBD: special case of slice?
char std_str_get(char *txt, slang_int_t pos)
{
    return txt[pos];
}

char *std_read_file(char *filename)
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
        std_panic("File not found!");
    }
    rt_decref(filename);
    return buffer;
}

slang_int_t std_file_open(char *filename, char *mode)
{
    FILE *f = fopen(filename, mode);
    if (!f)
    {
        printf("Error opening file: [%s] with mode [%s]\n", filename, mode);
        std_panic("std_file_open: Cannot open file");
    }
    return (slang_int_t)f;
}

void std_file_writeln(slang_int_t handle, char *line)
{
    if (handle != 0)
    {
        FILE *f = (FILE *)handle;
        fprintf(f, "%s\n", line);
    }
}

slang_int_t std_file_read_n_bytes(slang_int_t handle, uint8_t *buffer, slang_int_t bufsize)
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

slang_int_t std_file_write_n_bytes(slang_int_t handle, uint8_t *buffer, slang_int_t bufsize)
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

void std_file_close(slang_int_t handle)
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
    return main2();
}

slang_int_t std_get_n_args()
{
    return g_argc - 1;
}

char *std_get_arg(slang_int_t index)
{
    return g_argv[index + 1];
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

typedef struct rt_ref_mem_tag
{
    int count;
    int dummy;
} rt_ref_mem_t;

void *rt_malloc(int size)
{
    rt_ref_mem_t *ptr = malloc(size + sizeof(rt_ref_mem_t));
    ptr->count = 1;
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
    p->count -= 1;
#ifdef DEBUG_REFCOUNTING
    printf("DECREF New ref count: %d\n", p->count);
#endif
    if (p->count == 0)
    {
        // comment out below, to have malloc only!
        free(p);
    }
}
