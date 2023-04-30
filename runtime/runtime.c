
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void std_print(const char *message)
{
    puts(message);
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

int std_str_to_int(const char *x)
{
    // TODO!
    return 1337;
}

char *std_int_to_str(int x)
{
    char buffer[50];
    snprintf(buffer, 50, "%d", x);
    char *text = malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

char *std_float_to_str(double x)
{
    char buffer[50];
    snprintf(buffer, 50, "%f", x);
    char *text = malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
}

int std_str_len(const char *txt)
{
    return strlen(txt);
}

int std_ord(const char *txt)
{
    return txt[0];
}

char *std_str_slice(const char *txt, int begin, int end)
{
    const int size = end - begin;
    char *buffer = malloc(size + 1);
    memcpy(buffer, &txt[begin], size);
    buffer[size] = 0;
    return buffer;
}

// TBD: special case of slice?
char *std_str_get(const char *txt, int pos)
{
    char *buffer = malloc(2);
    buffer[0] = txt[pos];
    buffer[1] = 0;
    return buffer;
}

char *std_read_file(const char *filename)
{
    char *buffer = 0;
    FILE *f = fopen(filename, "r");
    if (f)
    {
        fseek(f, 0, SEEK_END);
        int length = ftell(f);
        buffer = malloc(length + 1);
        fseek(f, 0, SEEK_SET);
        fread(buffer, 1, length, f);
        buffer[length] = 0;
        fclose(f);
    }
    else
    {
        std_panic("File not found!");
    }
    return buffer;
}

char *rt_str_concat(const char *a, const char *b)
{
    char *buffer = malloc(strlen(a) + strlen(b) + 2);
    strcpy(buffer, a);
    strcat(buffer, b);
    return buffer;
}

int rt_str_compare(const char *a, const char *b)
{
    if (strcmp(a, b) == 0)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

void *rt_malloc(int size)
{
    return malloc(size);
}

// IDEA: use reference counting to free values.
void rt_incref(void *ptr)
{
}

void rt_decref(void *ptr)
{
}
