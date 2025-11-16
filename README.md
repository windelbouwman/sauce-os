# SAUCE-OS / Slang-lang

:construction: *Experimental language hacking!*

This is the home of the [slang-lang programming language](docs/slang-lang.md). Slang-lang
is a new general purpose programming language with the following features:

- Staticly typed. no runtime type errors
- Support for plain functions
- Support for plain structs
- Support for classes
- Checked exceptions. Exceptions must be handled.
- Support for generic types, like lists and hashmaps.
- Switch statement, to switch over integer constants
- If, While, Loop statements
- Enums, implemented as tagged unions, as in rust enums.
- Case expressions, to choose based on enum values
- Statements can be used as expressions
- Significant white space, blocks are indented with tabs, as in python
- Labeled function arguments
- Functions and types are module private by default, they can be explicitly made public
- No null pointer, there is an option type
- String interpolation

Hello world example:

```
from std import print

pub fn main() -> int:
    print("Hello world")
    0
```

The slang-lang compiler itself is written in slang-lang.
The compiler has several backends:

- :white_check_mark: C code. Compiles slang code into C code. This C code can then be compiled with a C compiler like GCC.
- :white_check_mark: python. Compiles slang code into python code. This backend is also implemented in the bootstrap compiler.
- :construction: x86. Compiles to native x86 code, usable on linux. Very limited at the moment.
- :construction: riscv. Compiles to native riscv code. Under construction, longer term goal.
- :construction: slang. Compiles slang code into .. slang. Useful for debugging the compiler.

Longer term goal is to develop an OS using the slang-lang language.

# Usage

Make sure you have the following installed:
- `make` to build using the Makefile
- `python3` for bootstrapping and testing, with these additional python packages:
  - `lark` for parsing
  - `networkx` for module dependency graphs
  - `pytest` for running the tests
  - `rich` for colorful console output
- `gcc` to compile C code

To build the slang-lang compiler and example programs, use make:

    $ make

This will perform the bootstrap sequence, and build all example programs.

Run the mandelbrot example:

    $ ./build/c/apps/mandel.exe

Run the compiler manually:

    $ ./build/compiler5 -h

To run the hello world example with the bytecode backend:

    $ ./build/compiler5 --run --backend-bc examples/snippets/hello_world.slang runtime/std.slang -v

To run the test suite:

    $ make test

# Compiler

There are two slang lang compilers. A bootstrap compiler (compiler1), implemented in python, and
the actual compiler written in slang lang itself.

## Bootstrapping sequence

To bootstrap the compiler, the following sequence is used:
- Compile `compiler-src` to `compiler-py1` using `compiler1`. This is the bootstrapping.
- Compile `compiler-src` to `compiler-py2` using `compiler-py1` with the backend python. Note that `compiler-py1` != `compiler-py2`, due to implementation differences between `compiler` and `compiler1`.
- Compile `compiler-src` to `compiler-py3` using `compiler-py2` with the backend python. Now we can check that `compiler-py2` == `compiler-py3`.
- Compile `compiler-src` to `compiler-c4` using `compiler-py3` with the C backend. Compile the c code to an executable.
- Compiler `compiler-src` to `compiler-c5` using `compiler-c4` with the C backend. Compile to executable with gcc. Now we can assert that `compiler-c4` == `compiler-c5`.

Now `compiler5` should be able to compile itself to identical C code.

## Compiler stages

The compiler consists of various stages:

- Parsing, consisting of the classic stages
  - Lexing: Source code is split into a logical token stream
  - Parsing: The token stream is analyzed using a recursive descent parser
  - AST: An abstract syntax tree is created
- Type checking
- Transformation
  - Transform for-loops into while loops
  - Transform classes into structs with functions
  - Enums are transformed into tagged unions
- Type checking (again). The transformed AST is type checked again, to ensure the transformations are valid.
- Code generation. Different outputs can be generated from the AST
  - python code can be directly generated from the AST
  - C code can be generated from the AST
  - Custom bytecode (BC) can be generated from the AST

# Libraries

A few libraries are provided in the `Libs` folder. The goal is a batteries included
idea, like in python.

Available libraries:

- base64, json and xml
- Regular expressions
- Compression, gzip and deflate
- Image formats, such as PNG, JPEG and QOI
- list, vector, hashmap, set and option types
- datetime

# License

This work is MIT licensed.

# Why this project?

This project is a recreational coding project. It's main purpose is an extended hobby.
