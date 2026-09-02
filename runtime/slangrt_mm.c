/*
Memory management runtime functions
*/

#include "slangrt.h"
#ifdef USE_SLAB_ALLOCATOR
#include "slangrt_slab.h"
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LOG(fmt, ...)                                                          \
    do {                                                                       \
        fprintf(stderr, "[%s:%s:%d] " fmt "\n", __func__, __FILE__, __LINE__,  \
                __VA_ARGS__);                                                  \
    } while (0)
#if 0
#define LOG_DEBUG(fmt, ...) LOG(fmt, __VA_ARGS__)
#else
#define LOG_DEBUG(fmt, ...)
#endif

#define HEAP_SRC_MALLOC 0x1
#ifdef USE_SLAB_ALLOCATOR
#define HEAP_SRC_SLAB_32 0x2
#define HEAP_SRC_SLAB_64 0x3
#endif

#define GC_KIND_NOPTRS 0x1
#define GC_KIND_OFFSETS 0x2
#define GC_KIND_POINTER_ARRAY 0x3

#define PTRSIZE sizeof(char*)

struct Allocation;

typedef struct GarbageCollector {
    int initialized;
#ifdef USE_SLAB_ALLOCATOR
    SmallSizeClass_t smallAllocator_32;
    SmallSizeClass_t smallAllocator_64;
#endif
} GarbageCollector_t;

// Allocation informational record
typedef struct Allocation {
    char kind;
    char heap;
    uint8_t magic1;
    uint8_t magic2;
    uint32_t count; // ref-count
    union {
        size_t size;        // size of the array of pointers
        const int* offsets; // offsets of pointers in this alloc (for structs)
    } data;
} Allocation_t;

static void gc_start(GarbageCollector_t* gc)
{
    LOG_DEBUG("Initialize GC %d", 1);
#ifdef USE_SLAB_ALLOCATOR
    gc->smallAllocator_64.obj_size = 64;
    gc->smallAllocator_64.slabs = NULL;
    gc->smallAllocator_32.obj_size = 32;
    gc->smallAllocator_32.slabs = NULL;
#endif
    gc->initialized = 42;
}

static void gc_stop(GarbageCollector_t* gc)
{
    gc->initialized = 0;
#ifdef USE_SLAB_ALLOCATOR
    small_finalize(&gc->smallAllocator_32);
    small_finalize(&gc->smallAllocator_64);
#endif
    LOG_DEBUG("Stopped GC %d", 1);
}

// Main API:
static void* gc_allocate(GarbageCollector_t* gc, size_t size)
{
    const size_t full_size = sizeof(Allocation_t) + size;

    if (gc->initialized != 42) {
        std_panic("GC not initialized");
    }

    // Create new block:
    Allocation_t* alloc = NULL;
#ifdef USE_SLAB_ALLOCATOR
    if (full_size < gc->smallAllocator_32.obj_size) {
        alloc = small_alloc(&gc->smallAllocator_32);
        alloc->heap = HEAP_SRC_SLAB_32;
    } else if (full_size < gc->smallAllocator_64.obj_size) {
        alloc = small_alloc(&gc->smallAllocator_64);
        alloc->heap = HEAP_SRC_SLAB_64;
    } else {
#endif
        alloc = (Allocation_t*)malloc(full_size);
        alloc->heap = HEAP_SRC_MALLOC;
#ifdef USE_SLAB_ALLOCATOR
    }
#endif
    alloc->magic1 = 0xCA;
    alloc->magic2 = 0xFE;
    alloc->count = 1; // start owned
    alloc->kind = GC_KIND_NOPTRS;
    alloc->data.offsets = NULL;

    void* ptr = (void*)(alloc + 1);

#ifdef DO_STRESS_TEST
// if (((intptr_t)(ptr) & 0x3) != 0) {
//     std_panic("Unaligned malloc!");
// }
#endif

    return ptr;
}

static void gc_free(GarbageCollector_t* gc, Allocation_t* alloc)
{
    switch (alloc->heap) {
    case HEAP_SRC_MALLOC:
        free(alloc);
        break;
#ifdef USE_SLAB_ALLOCATOR
    case HEAP_SRC_SLAB_32:
        small_free(&gc->smallAllocator_32, alloc);
        break;
    case HEAP_SRC_SLAB_64:
        small_free(&gc->smallAllocator_64, alloc);
        break;
#endif
    default:
        break;
    }
}

// RT-memory API:

// Global garbage collector:
GarbageCollector_t g_gc;

void __attribute__((constructor(103))) rt_gc_init()
{
    gc_start(&g_gc);
}

void __attribute__((destructor(103))) rt_gc_finalize()
{
    gc_stop(&g_gc);
}

void rt_inc_ref(void* ptr)
{
    if (ptr == NULL || (((uintptr_t)ptr & 1) != 0)) {
        return;
    }
    Allocation_t* alloc = ((Allocation_t*)ptr) - 1;
    if (alloc->magic1 != 0xCA) {
        std_panic("Bad magic1!");
    }
    if (alloc->magic2 != 0xFE) {
        std_panic("Bad magic2!");
    }
    alloc->count++;
}

void rt_dec_ref(void* ptr)
{
    if (ptr == NULL || (((uintptr_t)ptr & 1) != 0)) {
        return;
    }
    Allocation_t* alloc = ((Allocation_t*)ptr) - 1;

    if (alloc->magic1 != 0xCA) {
        std_panic("Bad magic1!");
    }
    if (alloc->magic2 != 0xFE) {
        std_panic("Bad magic2!");
    }

    if (alloc->count == 0) {
        std_panic("Double free!");
    }

    alloc->count--;

    if (alloc->count == 0) {
        // Free, but also free referenced data.

        switch (alloc->kind) {
        case GC_KIND_NOPTRS:
            // This allocation contains no pointers
            break;
        case GC_KIND_OFFSETS:
            // Walk list with offsets, these are pointers offsets in the
            // allocation.
            for (int i = 0; alloc->data.offsets[i] >= 0; i++) {
                char* field_pointer = ((char*)ptr) + alloc->data.offsets[i];
                void* child_ptr = *(void**)field_pointer;
                rt_dec_ref(child_ptr);
            }
            break;
        case GC_KIND_POINTER_ARRAY:
            for (int i = 0; i < alloc->data.size; i++) {
                void** element_ptr = ((void**)ptr) + i;
                void* child_ptr = *(void**)element_ptr;
                rt_dec_ref(child_ptr);
            }
            break;
        default:
            std_panic("Unsupported alloc kind");
            break;
        }

        // Free memory back! Yay!
        gc_free(&g_gc, alloc);
    }
}

void rt_replace_owned(void** slot, void* value)
{
    void* old_value = *slot;
    *slot = value;
    if (old_value != NULL) {
        rt_dec_ref(old_value);
    }
}

void* rt_malloc_str(size_t size)
{
    return gc_allocate(&g_gc, size);
}

void* rt_malloc(size_t size)
{
    return gc_allocate(&g_gc, size);
}

void* rt_malloc_struct(size_t size, const int* ref_offsets)
{
    void* ptr = gc_allocate(&g_gc, size);
    if (ref_offsets != NULL) {
        Allocation_t* alloc = ((Allocation_t*)ptr) - 1;
        alloc->kind = GC_KIND_OFFSETS;
        alloc->data.offsets = ref_offsets;
        // Clear eventual pointers:
        memset(ptr, 0, size);
    }
    return ptr;
}

void* rt_malloc_array(size_t num, size_t size,
                      slang_bool_t elements_are_pointers)
{
    void* ptr = gc_allocate(&g_gc, num * size);
    if (elements_are_pointers != 0) {
        memset(ptr, 0, num * size);
        Allocation_t* alloc = ((Allocation_t*)ptr) - 1;
        alloc->kind = GC_KIND_POINTER_ARRAY;
        alloc->data.size = num;
    }
    return ptr;
}
