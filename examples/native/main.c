
#include <stdio.h>

extern int t1_add(int, int);
extern int t1_sub(int, int);

int main()
{
    printf("ADD: %d (should be 61)\n", t1_add(9, 10));
    printf("SUB: %d (should be -2002)\n", t1_sub(9, 10));
    return 0;
}
