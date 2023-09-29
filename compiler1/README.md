Bootstrapping compiler.

Idea: implement a compiler in python, transforming source-code to C++ code.

# Usage

    python -m compiler1 examples/mandel.slang --backend py

# Dependencies

- lark -> parsing
- networkx -> graph algorithms
- rich -> fancy logging

# Profiling

Profile the bootstrap compiler:

    $ python -m cProfile -o profiled.out bootstrap.py
    $ pyprof2calltree -i profiled.out -k

Or, profile the C version:

    $ valgrind --tool=callgrind ./compiler5 -cv2 compiler/*.slang
    $ kcachegrind callgrind.out.4090
