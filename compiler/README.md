# Introduction

Slang-lang compiler, implemented in slang-lang!

# Usage

Compile the `examples/mandel.slang` example to python code:

    $ ./build/compiler4 -py examples/mandel.slang runtime/std.slang

Compile the `examples/hello-world.slang` example to WebAssembly:

    $ ./build/compiler4 -wasm examples/hello-world.slang runtime/std.slang

Compile the `examples/hello-world.slang` example to C code:

    $ ./build/compiler4 -c examples/hello-world.slang runtime/std.slang

# Bootstrapping

There are several compilers:

- compiler : Slang compiler implemented in slang
- compiler1 : Slang compiler implemented in python

Use this script to bootstrap the slang compiler:

    $ bash bootstrap2.sh

Or, manually perform the steps in the bootstrap2.sh.

Use this bootstrap script to compile compiler using compiler1:

    $ python bootstrap.py

# Design

## Lexer

We use a hand written lexer, which scans each character, and produces tokens.
To handle whitespace, the tokens are postprocessed, and indent and dedent tokens
are inserted into the token stream.

## Parser

We use recursive descent parser, which processes a token stream into an abstract syntax tree (AST).

## Passes

We have several passes over the AST. For this we use the visitor pattern.

- name binding
- name resolution
- type evaluation
- type checking
- transformations
- type checking (again)
- code generation

## Name binding and resolution

First, scopes are filled for the whole program.

In a next pass over the AST, names are resolved using the filled in symbol tables.

## Pass3

In pass3 types are evaluated.

## Type checker

Here we assign types to all expressions in the AST.

# Profiling

Profile the C version:

    $ valgrind --tool=callgrind ./compiler5 -c compiler/*.slang
    $ kcachegrind callgrind.out.4090
