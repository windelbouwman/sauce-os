
#ifndef SLANGRT_H
#define SLANGRT_H

#include <stdint.h>
#include <setjmp.h>

// runtime types:
typedef intptr_t slang_int_t;
typedef double slang_float_t;

typedef intptr_t slang_bool_t;
typedef uint8_t slang_uint8_t;
typedef uint16_t slang_uint16_t;
typedef uint32_t slang_uint32_t;
typedef intptr_t slang_uint64_t;
typedef int8_t slang_int8_t;
typedef int16_t slang_int16_t;
typedef int32_t slang_int32_t;
typedef intptr_t slang_int64_t;
typedef float slang_float32_t;
typedef double slang_float64_t;

typedef struct slang_exception_handler slang_exception_handler_t;
struct slang_exception_handler
{
    jmp_buf buf;
    slang_exception_handler_t *prev;
};

// runtime globals:
extern slang_exception_handler_t* g_except_hook;
extern void* g_except_value;

// runtime functions:
void* rt_malloc(size_t size);
void *rt_malloc_with_destroyer(size_t size, void (*destroyer)(void*));
void rt_incref(void *ptr);
void rt_decref(void *ptr);
char* rt_str_new(const char *);
// void slangrt_unreachable();

#endif
