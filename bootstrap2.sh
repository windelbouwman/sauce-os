#!/bin/bash

set -euo pipefail

COMPILER_SRCS="compiler/*.slang compiler/**/*.slang"
COMPILER1="build/tmp-compiler.py"
COMPILER2="build/tmp-compiler2.py"
COMPILER3="build/tmp-compiler3.py"
COMPILER4="build/tmp-compiler4.c"
COMPILER6="build/tmp-compiler6.py"

mkdir -p build
# Compile compiler with bootstrap compiler
echo "Compile compiler with bootstrap compiler into ${COMPILER1}"
python bootstrap.py

echo "Compiling compiler with ${COMPILER1} into ${COMPILER2}"

echo "#!/usr/bin/env python" > ${COMPILER2}
python ${COMPILER1} ${COMPILER_SRCS} >> ${COMPILER2}
chmod +x ${COMPILER2}

echo "Bootstrap again! Compile compiler with ${COMPILER2} into ${COMPILER3}"

echo "#!/usr/bin/env python" > ${COMPILER3}
python ${COMPILER2} ${COMPILER_SRCS} >> ${COMPILER3}
chmod +x ${COMPILER3}

# Compiler 1 and 2 are different:
# - They are produced from the same source, but using a different compiler.

# Compiler 2 and 3 should be the same:
diff ${COMPILER2} ${COMPILER3}

echo "Compiling compiler4"
python ${COMPILER3} -cv2 ${COMPILER_SRCS} | sed '/^# /d' > build/tmp-compiler4.c
gcc -o build/compiler4 build/tmp-compiler4.c runtime/runtime.c

echo "Compiling compiler5"
./build/compiler4 -cv2 ${COMPILER_SRCS} | sed '/^# /d' > build/tmp-compiler5.c
gcc -o build/compiler5 build/tmp-compiler5.c runtime/runtime.c

diff build/tmp-compiler4.c build/tmp-compiler5.c

echo "Compiling compiler6"
echo "#!/usr/bin/env python" > ${COMPILER6}
./build/compiler5 ${COMPILER_SRCS} >> ${COMPILER6}

echo "OK"
