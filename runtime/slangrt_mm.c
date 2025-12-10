/*
Memory management runtime functions

See also:
https://github.com/mkirchner/gc
*/

#include "slangrt.h"
#include <setjmp.h>
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

#define GC_TAG_NONE 0x0
#define GC_TAG_MARK 0x2

#define GC_KIND_OPAQUE 0x0
#define GC_KIND_NOPTRS 0x1
#define GC_KIND_OFFSETS 0x2

#define PTRSIZE sizeof(char*)

struct AllocationMap;
struct Allocation;

typedef struct GarbageCollector {
    void* bos; // bottom of stack
    size_t limit;
    struct AllocationMap* alloc_map;
} GarbageCollector_t;

// Hash map of allocations
// Maps pointers to alloc info records
typedef struct AllocationMap {
    size_t capacity;
    size_t size;
    struct Allocation** allocs;
} AllocationMap_t;

// Allocation informational record
typedef struct Allocation {
    void* ptr;
    size_t size;
    char tag;
    char kind;
    const int* offsets;
    struct Allocation* next;
} Allocation_t;

static size_t gc_hash(void* ptr)
{
    return ((uintptr_t)ptr) >> 3;
}

static Allocation_t* gc_allocation_new(size_t size, char kind,
                                       const int* offsets)
{
    Allocation_t* alloc = (Allocation_t*)malloc(sizeof(Allocation_t) + size);

    void* ptr = (void*)(alloc + 1);

    alloc->ptr = ptr;
    alloc->size = size;
    alloc->tag = GC_TAG_NONE;
    alloc->kind = kind;
    alloc->offsets = offsets;
    alloc->next = NULL;
    return alloc;
}

static AllocationMap_t* gc_allocation_map_new(size_t capacity)
{
    AllocationMap_t* map = (AllocationMap_t*)malloc(sizeof(AllocationMap_t));
    map->capacity = capacity;
    map->size = 0;
    map->allocs = (Allocation_t**)calloc(map->capacity, sizeof(Allocation_t*));
    return map;
}

static void gc_allocation_map_delete(AllocationMap_t* map)
{
    free(map->allocs);
    free(map);
}

static void gc_allocation_map_resize(AllocationMap_t* map, size_t new_capacity)
{
    LOG_DEBUG("Resize hashmap capacity from %d to %d", map->capacity,
              new_capacity);

    Allocation_t** resized_allocs = calloc(new_capacity, sizeof(Allocation_t*));

    // Copy allocs into new hashmap:
    for (size_t index = 0; index < map->capacity; index++) {
        Allocation_t* alloc = map->allocs[index];
        while (alloc) {
            Allocation_t* next = alloc->next;
            size_t new_index = gc_hash(alloc->ptr) % new_capacity;
            alloc->next = resized_allocs[new_index];
            resized_allocs[new_index] = alloc;
            alloc = next;
        }
    }

    free(map->allocs);
    map->allocs = resized_allocs;
    map->capacity = new_capacity;
}

static void gc_allocation_map_resize_to_fit(AllocationMap_t* map)
{
    const double load_factor = (double)map->size / (double)map->capacity;
    if (load_factor > 0.8) {
        gc_allocation_map_resize(map, map->capacity * 2);
    } else if ((load_factor < 0.2) && (map->capacity > 100)) {
        // Shrink the map!
        gc_allocation_map_resize(map, map->capacity / 2);
    }
}

static Allocation_t* gc_allocation_map_get(AllocationMap_t* map, void* ptr)
{
    size_t index = gc_hash(ptr) % map->capacity;
    Allocation_t* cur = map->allocs[index];
    while (cur) {
        if (cur->ptr == ptr) {
            return cur;
        }
        cur = cur->next;
    }
    return NULL;
}

static void gc_allocation_map_put(AllocationMap_t* map, Allocation_t* alloc)
{
    size_t index = gc_hash(alloc->ptr) % map->capacity;
    Allocation_t* cur = map->allocs[index];
    Allocation_t* prev = NULL;

    // Check for existing record:
    while (cur) {
        if (cur->ptr == alloc->ptr) {
            LOG_DEBUG("DUPLICATE PTR %X", ptr);
            alloc->next = cur->next;
            if (prev) {
                prev->next = alloc;
            } else {
                map->allocs[index] = alloc;
            }
            exit(1);
            return;
        }
        prev = cur;
        cur = cur->next;
    }

    // No existing record, insert in front of chain list:
    alloc->next = map->allocs[index];
    map->allocs[index] = alloc;
    map->size++;
    gc_allocation_map_resize_to_fit(map);
}

static void gc_allocation_map_remove(AllocationMap_t* map, Allocation_t* alloc)
{
    size_t index = gc_hash(alloc->ptr) % map->capacity;
    Allocation_t* cur = map->allocs[index];
    Allocation_t* prev = NULL;

    while (cur) {
        Allocation_t* next = cur->next;
        if (cur == alloc) {
            if (prev) {
                prev->next = cur->next;
            } else {
                map->allocs[index] = cur->next;
            }
            map->size--;
        } else {
            prev = cur;
        }
        cur = next;
    }
}

static void gc_mark_alloc(GarbageCollector_t* gc, void* ptr)
{
    Allocation_t* alloc = gc_allocation_map_get(gc->alloc_map, ptr);
    if (alloc && !(alloc->tag & GC_TAG_MARK)) {
        alloc->tag |= GC_TAG_MARK;

        switch (alloc->kind) {
        case GC_KIND_NOPTRS:
            // This allocation contains no pointers
            break;
        case GC_KIND_OFFSETS:
            // Walk list with offsets, these are pointers offsets in the
            // allocation.
            for (int i = 0; alloc->offsets[i] >= 0; i++) {
                char* p = (char*)alloc->ptr + alloc->offsets[i];
                gc_mark_alloc(gc, *(void**)p);
            }
            break;
        default:
            // Scan the whole blob conservative:
            for (char* p = (char*)alloc->ptr;
                 p <= (char*)alloc->ptr + alloc->size - PTRSIZE; ++p) {
                gc_mark_alloc(gc, *(void**)p);
            }
            break;
        }
    }
}

static void gc_mark_stack(GarbageCollector_t* gc)
{
    void* tos = __builtin_frame_address(0);
    void* bos = gc->bos;
    for (char* p = (char*)tos; p <= (char*)bos - PTRSIZE; ++p) {
        gc_mark_alloc(gc, *((void**)p));
    }
}

static void gc_mark_roots(GarbageCollector_t* gc)
{
    // Mark global variables
    // TODO!
}

static void gc_mark(GarbageCollector_t* gc)
{
    gc_mark_roots(gc);
    // TBD: why would below be required?
    void (*volatile _mark_stack)(GarbageCollector_t*) = gc_mark_stack;
    jmp_buf ctx;
    memset(&ctx, 0, sizeof(jmp_buf));
    setjmp(ctx);
    _mark_stack(gc);
}

static void gc_sweep(GarbageCollector_t* gc)
{
    size_t harvest = 0;
    for (size_t index = 0; index < gc->alloc_map->capacity; index++) {
        Allocation_t* alloc = gc->alloc_map->allocs[index];
        while (alloc) {
            if (alloc->tag & GC_TAG_MARK) {
                alloc->tag &= ~GC_TAG_MARK;
                alloc = alloc->next;
            } else {
                harvest += 1;
                Allocation_t* next = alloc->next;
                // Free non-reachable alloc:
                gc_allocation_map_remove(gc->alloc_map, alloc);
                free(alloc);
                alloc = next;
            }
        }
    }
    LOG_DEBUG("Collected: %d allocations", harvest);
}

static void gc_run(GarbageCollector_t* gc)
{
    LOG_DEBUG("Garbage collecting on %d allocations", gc->alloc_map->size);
    gc_mark(gc);
    gc_sweep(gc);
}

static void gc_start(GarbageCollector_t* gc, void* bos)
{
    LOG_DEBUG("Initialize GC: %X", bos);
    gc->bos = bos;
    gc->alloc_map = gc_allocation_map_new(1024);
    gc->limit = gc->alloc_map->size + gc->alloc_map->capacity;
}

static void gc_stop(GarbageCollector_t* gc)
{
    gc_sweep(gc);
    gc_allocation_map_delete(gc->alloc_map);
}

// Main API:
void* gc_allocate(GarbageCollector_t* gc, size_t size, char kind,
                  const int* offsets)
{
    // If we need garbage collection, run it
    if (gc->alloc_map->size > gc->limit) {
        // gc->limit *= 3;
        // TODO
        gc_run(gc);
        gc->limit = gc->alloc_map->size + gc->alloc_map->capacity;
        // gc->limit = gc->alloc_map->size + (gc->alloc_map->capacity -
        // gc->alloc_map->size) / 2;
    }

    // void* ptr = malloc(sizeof(Allocation_t) + size);
    Allocation_t* alloc = gc_allocation_new(size, kind, offsets);

    if (((intptr_t)(alloc->ptr) & 0x3) != 0) {
        puts("Unaligned malloc!");
        exit(1);
    }
    gc_allocation_map_put(gc->alloc_map, alloc);
    // LOG_DEBUG("alloc: size=%d capacity=%d", gc->alloc_map->size,
    // gc->alloc_map->capacity);
    return alloc->ptr;
}

// RT-memory API:

// Global garbage collector:
GarbageCollector_t g_gc;

void rt_gc_init(void* bos)
{
    gc_start(&g_gc, bos);
}

void rt_gc_finalize()
{
    gc_stop(&g_gc);
}

void* rt_malloc_str(size_t size)
{
    return gc_allocate(&g_gc, size, GC_KIND_NOPTRS, NULL);
}

void* rt_malloc(size_t size)
{
    return gc_allocate(&g_gc, size, GC_KIND_OPAQUE, NULL);
}

void* rt_malloc_with_destroyer(size_t size, const int* ref_offsets)
{
    // return malloc(size);

    void* ptr = gc_allocate(&g_gc, size, GC_KIND_OFFSETS, ref_offsets);
    return ptr;
}
