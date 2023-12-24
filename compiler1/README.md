# Slang lang bootstrapping compiler.

A compiler written in python, compiling slang source-code to python code.

# Installation

Dependencies:

- lark -> parsing
- networkx -> graph algorithms
- rich -> fancy logging

Install dependencies from requirements.txt file:

    $ pip install --requirement compiler1/requirements.txt

# Usage

    $ python -m compiler1 examples/mandel.slang --backend py

# Profiling

Profile the bootstrap compiler:

    $ python -m cProfile -o profiled.out bootstrap.py
    $ pyprof2calltree -i profiled.out -k
