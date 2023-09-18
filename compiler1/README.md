Bootstrapping compiler.

Idea: implement a compiler in python, transforming source-code to C++ code.

# Usage

    python -m compiler1 examples/mandel.slang --backend py

# Dependencies

- lark -> parsing
- networkx -> graph algorithms
- rich -> fancy logging

# Profiling

    $ python -m cProfile -o profiled.out bootstrap.py
    $ pyprof2calltree -i profiled.out -k
