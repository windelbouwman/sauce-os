#!/bin/bash

set -euo pipefail

COMPILER_SRCS="compiler/main.slang Libs/compiler/*.slang Libs/compiler/**/*.slang Libs/base/*.slang runtime/std.slang"
COMPILER1="build/tmp-compiler.py"
COMPILER2="build/tmp-compiler2.py"
COMPILER3="build/tmp-compiler3.py"
COMPILER4="build/tmp-compiler4.c"
COMPILER6="build/tmp-compiler6.py"

mkdir -p build

# Compile compiler with bootstrap compiler
echo "Compile compiler with bootstrap compiler into ${COMPILER1}"
python bootstrap.py
cp runtime/slangrt.py build

echo "Compiling compiler with ${COMPILER1} into ${COMPILER2}"

python ${COMPILER1} --backend-py -o ${COMPILER2} ${COMPILER_SRCS}

echo "Bootstrap again! Compile compiler with ${COMPILER2} into ${COMPILER3}"

python ${COMPILER2} --backend-py -o ${COMPILER3} ${COMPILER_SRCS}

# Compiler 1 and 2 are different:
# - They are produced from the same source, but using a different compiler.

# Compiler 2 and 3 should be the same:
diff ${COMPILER2} ${COMPILER3}

echo "Compiling compiler4"
python ${COMPILER3} --backend-c -o build/tmp-compiler4.c ${COMPILER_SRCS}
gcc -o build/compiler4 build/tmp-compiler4.c runtime/slangrt.c runtime/slangrt_mm.c -lm -Iruntime

echo "Compiling compiler5"
./build/compiler4 --backend-c -o build/tmp-compiler5.c ${COMPILER_SRCS}
gcc -o build/compiler5 build/tmp-compiler5.c runtime/slangrt.c runtime/slangrt_mm.c -lm -Iruntime

diff build/tmp-compiler4.c build/tmp-compiler5.c

echo "Compiling compiler6"
./build/compiler5 --backend-py -o ${COMPILER6} ${COMPILER_SRCS}

echo "OK"
