#include "slangrt.h"

extern slang_int_t main_main();

int main(int argc, char** argv)
{
    rt_init(argc, argv);
    int res = main_main();
    return res;
}
