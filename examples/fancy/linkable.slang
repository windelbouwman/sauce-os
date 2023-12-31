

extern fn outp1(port: int, value: int)
extern fn display(value: int)

fn configure(base: int):
    display(1)
    #outp1(base + 1, 55)
    #outp1(base + 2, 0xFF)

    #outp1(base + 1, 0)
    outp1(base + 2, 100)

    #display(0)

