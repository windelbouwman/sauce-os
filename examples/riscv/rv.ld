
MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K
}

ENTRY(_start)

SECTIONS {
    .text : {
        *(.boot)
        *(.text)
    } > RAM

    . = ALIGN(16);
    __stack_top = .;
    __stack_size = 4K;
    __stack_bottom = __stack_top - __stack_size;
}
