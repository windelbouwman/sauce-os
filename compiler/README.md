Slang compiler (implemented in slang!)

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
