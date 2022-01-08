
#include <stdint.h>

volatile static uint16_t *screen_buffer;
static int row, column;

void putc(unsigned char ch)
{
    screen_buffer[column] = (0x0F << 8) | ch;
    column += 1;
}

void std_print(char *txt)
{
    while (*txt)
    {
        putc(*txt++);
    }
}

extern void fuu();

void kernel_main()
{
    screen_buffer = (uint16_t *)0xb8000;
    row = 0;
    column = 0;

    screen_buffer[0] = (65 | (15 << 8));

    putc('A');
    putc('B');
    putc('C');

    std_print("Bla bla bla...");

    fuu();
}
