
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

char *std_int_to_str(int x)
{
    char buffer[50];
    snprintf(buffer, 50, "%d", x);
    char *text = malloc(strlen(buffer) + 1);
    strcpy(text, buffer);
    return text;
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

unsigned char rt_str_compare(const char *a, const char *b)
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
