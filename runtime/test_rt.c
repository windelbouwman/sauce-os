/*
Test program to test automatic memory management.

Iterate with:

    $ watchexec -w runtime make mm

*/

#include "slangrt.h"
#include <stdio.h>

void test_string()
{
    printf("test rt_malloc_str(200)....");
    void* str_pointer = rt_malloc_str(200);
    rt_inc_ref(str_pointer);
    rt_dec_ref(str_pointer); // OK
    rt_dec_ref(str_pointer); // OK --> free
    // rt_dec_ref(str_pointer); // not ok
    printf("OK.\n");
}

void test_small_str()
{
    // small object
    printf("test rt_malloc_str(16)....");
    void* str_pointer = rt_malloc_str(16);
    rt_inc_ref(str_pointer);
    rt_dec_ref(str_pointer); // OK
    rt_dec_ref(str_pointer); // OK --> free
    // rt_dec_ref(str_pointer); // not ok
    printf("OK.\n");
}

void test_small_objects()
{
    // small object
    printf("test small_objects....");
    void* obj_1 = rt_malloc_str(16);
    void* obj_2 = rt_malloc_str(16);
    void* obj_3 = rt_malloc_str(16);
    rt_dec_ref(obj_2); // OK
    rt_dec_ref(obj_1); // OK
    void* obj_4 = rt_malloc_str(16);
    void* obj_5 = rt_malloc_str(16);
    rt_dec_ref(obj_3); // OK
    void* obj_6 = rt_malloc_str(16);
    void* obj_7 = rt_malloc_str(16);
    rt_dec_ref(obj_7); // OK
    rt_dec_ref(obj_6); // OK
    rt_dec_ref(obj_4); // OK
    rt_dec_ref(obj_5); // OK
    printf("OK.\n");
}

void test_array()
{
    printf("arrays...");
    void** arr = rt_malloc_array(1, sizeof(void*), 1);
    arr[0] = rt_malloc_str(200);
    rt_dec_ref(arr); // OK
    printf("OK.\n");
}

int main(int argc, char** argv)
{
    rt_init(argc, argv);

    test_string();
    test_small_str();
    test_small_objects();
    test_array();

    return 0;
}
