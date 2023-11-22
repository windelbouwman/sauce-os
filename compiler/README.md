# Introduction

Slang-lang compiler, implemented in slang-lang!

# Usage

# Bootstrapping

There are several compilers:

- compiler : Slang compiler implemented in slang
- compiler1 : Slang compiler implemented in python

Use compiler1 for bootstrapping:

    $ python -m compiler1 compiler/*.slang --backend py

This will compile the slang compiler written in slang-lang using the slang compiler written in python.

Use this bootstrap script to compile compiler using compiler1:

    $ python bootstrap.py

Now, you can use compiler to compile itself:

    $ python tmp-compiler.py compiler/*.slang > tmp2.py

# Design

## Lexer

We use a hand written parser, which scans each character, and produces tokens.
To handle whitespace, the tokens are postprocessed, and indent and dedent tokens
are inserted into the token stream.

## Parser

We use recursive descent parser, which processes a token stream into an abstract syntax tree (AST).

## Passes

We have several passes over the AST. For this we use the visitor pattern.

- name binding
- name resolve
- type evaluation
- type checking
- transformations
- type checking (again)

## Name binding

First, scopes are filled for the whole program.

In a next pass over the AST, names are resolved using the filled in symbol tables.

## Pass3

In pass3 types are evaluated.

## Type checker

# Profiling

Profile the C version:

    $ valgrind --tool=callgrind ./compiler5 -c compiler/*.slang
    $ kcachegrind callgrind.out.4090
