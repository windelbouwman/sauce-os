# SAUCE-OS

:construction: *Experimental language hacking!*

This is the home of the [slang-lang programming language](docs/slang-lang.md).

Example slang-lang hello world:

```
from std import print
fn main() -> int:
    print("Hello world")
    0
```

# Usage

To build the slang-lang compiler and example programs, use make:

    $ make

Run the mandelbrot example:

    $ ./build/c/apps/mandel.exe

Run the compiler manually:

    $ ./build/compiler5 -h

To run the unit test suite:

    $ make test

# Compiler

- minimal viable compiler:
  - language
    - functions
    - structs
    - if/then/else
  - OS api:
    - file I/O
    - console output

# Libraries

Common libraries

- regular expressions
- GUI
- file I/O
- parser/lexer stuff

# Idea section

Idea list:

- new language(s)
- compiler in python using LLVM-ir?

- minimal viable compiler:
  - language
    - functions
    - structs
    - if/then/else
  - OS api:
    - file I/O
    - console output
