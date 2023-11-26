# Slang lang bootstrapping compiler.

A compiler written in python, compiling slang source-code to python code.

# Usage

    $ python -m compiler1 examples/mandel.slang --backend py

# Dependencies

- lark -> parsing
- networkx -> graph algorithms
- rich -> fancy logging

# Profiling

Profile the bootstrap compiler:

    $ python -m cProfile -o profiled.out bootstrap.py
    $ pyprof2calltree -i profiled.out -k
