Slang compiler (implemented in slang!)

# Bootstrapping using compiler1

Use compiler1 for bootstrapping:

    $ cd my_clone_folder
    $ python -m compiler1 compiler/*.slang --backend py -v --run-code

This will compile the slang compiler written in slang-lang using the slang compiler written in python.
