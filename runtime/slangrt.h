
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

// Boxing and unboxing operations
#define SLANG_BOX_CHAR(X) slangrt_box_char(X)
#define SLANG_UNBOX_CHAR(X) slangrt_unbox_char(X)
void* slangrt_box_char(char);
char slangrt_unbox_char(void*);

#define SLANG_BOX_BOOL(X) slangrt_box_bool(X)
#define SLANG_UNBOX_BOOL(X) slangrt_unbox_bool(X)
void* slangrt_box_bool(slang_bool_t);
slang_bool_t slangrt_unbox_bool(void*);

#define SLANG_BOX_INT8(X) slangrt_box_int8(X)
#define SLANG_UNBOX_INT8(X) slangrt_unbox_int8(X)
#define SLANG_BOX_INT16(X) slangrt_box_int16(X)
#define SLANG_UNBOX_INT16(X) slangrt_unbox_int16(X)
#define SLANG_BOX_INT32(X) slangrt_box_int32(X)
#define SLANG_UNBOX_INT32(X) slangrt_unbox_int32(X)
#define SLANG_BOX_INT64(X) slangrt_box_int64(X)
#define SLANG_UNBOX_INT64(X) slangrt_unbox_int64(X)
void* slangrt_box_int8(slang_int8_t);
slang_int8_t slangrt_unbox_int8(void*);
void* slangrt_box_int16(slang_int16_t);
slang_int16_t slangrt_unbox_int16(void*);
void* slangrt_box_int32(slang_int32_t);
slang_int32_t slangrt_unbox_int32(void*);
void* slangrt_box_int64(slang_int64_t);
slang_int64_t slangrt_unbox_int64(void*);

#define SLANG_BOX_UINT8(X) slangrt_box_uint8(X)
#define SLANG_UNBOX_UINT8(X) slangrt_unbox_uint8(X)
#define SLANG_BOX_UINT16(X) slangrt_box_uint16(X)
#define SLANG_UNBOX_UINT16(X) slangrt_unbox_uint16(X)
#define SLANG_BOX_UINT32(X) slangrt_box_uint32(X)
#define SLANG_UNBOX_UINT32(X) slangrt_unbox_uint32(X)
#define SLANG_BOX_UINT64(X) slangrt_box_uint64(X)
#define SLANG_UNBOX_UINT64(X) slangrt_unbox_uint64(X)
void* slangrt_box_uint8(slang_uint8_t);
slang_uint8_t slangrt_unbox_uint8(void*);
void* slangrt_box_uint16(slang_uint16_t);
slang_uint16_t slangrt_unbox_uint16(void*);
void* slangrt_box_uint32(slang_uint32_t);
slang_uint32_t slangrt_unbox_uint32(void*);
void* slangrt_box_uint64(slang_uint64_t);
slang_uint64_t slangrt_unbox_uint64(void*);

#define SLANG_BOX_FLOAT32(X) slangrt_box_float32(X)
#define SLANG_UNBOX_FLOAT32(X) slangrt_unbox_float32(X)
#define SLANG_BOX_FLOAT64(X) slangrt_box_float64(X)
#define SLANG_UNBOX_FLOAT64(X) slangrt_unbox_float64(X)

void* slangrt_box_float32(slang_float32_t);
slang_float32_t slangrt_unbox_float32(void*);
void* slangrt_box_float64(slang_float64_t);
slang_float64_t slangrt_unbox_float64(void*);

// Unreachable instruction:
#if defined __GNUC__
#define SLANG_UNREACHABLE __builtin_unreachable();
#elif defined _MSC_VER
#define SLANG_UNREACHABLE __assume(0);
#else
#error unsupported compiler
#endif

#endif
