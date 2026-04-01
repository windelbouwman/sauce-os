#include "slangrt.h"

extern slang_int_t main_main();

int main(int argc, char** argv)
{
    rt_init(argc, argv);
    rt_gc_init(&argc);
    int res = main_main();
    rt_gc_finalize();
    return res;
}
