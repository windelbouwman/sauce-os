Bootstrapping compiler.

Idea: implement a compiler in python, transforming source-code to C++ code.

Usage:

    python -m compiler1 examples/mandel.slang --output tmp.cpp
    g++ tmp.cpp runtime/runtime.cpp
    ./a.out
