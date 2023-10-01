
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Config:
// #define DEBUG_REFCOUNTING

extern int main2();
void *rt_malloc(int size);
void rt_incref(void *ptr);
void rt_decref(void *ptr);

void std_print(char *message)
{
    puts(message);
    rt_decref(message);
}

void std_putc(const char *ch)
{
    // TBD: do we require special char type?
    putchar(ch[0]);
}

void std_exit(int code)
{
    exit(code);
}

void std_panic(const char *message)
{
    puts(message);
    std_exit(1);
}

int std_str_to_int(char *x)
{
    int value = strtol(x, NULL, 10);
    rt_decref(x);
    return value;
}

char *std_int_to_str(int x)
{
    char buffer[50];
    snprintf(buffer, 50, "%d", x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

char *std_float_to_str(double x)
{
    char buffer[50];
    snprintf(buffer, 50, "%f", x);
    char *text = rt_malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

double std_str_to_float(char *x)
{
    double value = strtod(x, NULL);
    return value;
}

char *std_char_to_str(char x)
{
    char *text = rt_malloc(2);
    text[0] = x;
    text[1] = 0;
    return text;
}

int std_str_len(char *txt)
{
    const int len = strlen(txt);
    rt_decref(txt);
    return len;
}

int std_ord(char c)
{
    return c;
}

char std_chr(int val)
{
    return val;
}

char *std_str_slice(char *txt, int begin, int end)
{
    const int size = end - begin;
    char *buffer = rt_malloc(size + 1);
    memcpy(buffer, &txt[begin], size);
    rt_decref(txt);
    buffer[size] = 0;
    return buffer;
}

// TBD: special case of slice?
char std_str_get(char *txt, int pos)
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

int g_argc;
char **g_argv;

int main(int argc, char **argv)
{
    g_argc = argc;
    g_argv = argv;
    return main2();
}

int std_get_n_args()
{
    return g_argc - 1;
}

char *std_get_arg(int index)
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
