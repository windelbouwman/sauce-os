#!/bin/bash

set -euo pipefail

COMPILER1="tmp-compiler.py"
COMPILER2="tmp-compiler2.py"
COMPILER3="tmp-compiler3.py"
COMPILER6="tmp-compiler6.py"

# Compile compiler with bootstrap compiler
echo "Compile compiler with bootstrap compiler into ${COMPILER1}"
python bootstrap.py

echo "Compiling compiler with ${COMPILER1} into ${COMPILER2}"

echo "#!/usr/bin/env python" > ${COMPILER2}
python ${COMPILER1} compiler/*.slang >> ${COMPILER2}
chmod +x ${COMPILER2}

echo "Bootstrap again! Compile compiler with ${COMPILER2} into ${COMPILER3}"

echo "#!/usr/bin/env python" > ${COMPILER3}
python ${COMPILER2} compiler/*.slang >> ${COMPILER3}
chmod +x ${COMPILER3}

# Compiler 1 and 2 are different:
# - They are produced from the same source, but using a different compiler.

# Compiler 2 and 3 should be the same:
diff ${COMPILER2} ${COMPILER3}

echo "Compiling compiler4"
python ${COMPILER3} -cv2 compiler/*.slang | sed '/^# /d' > tmp-compiler4.c
gcc -Wno-incompatible-pointer-types -Wno-int-conversion -o compiler4 tmp-compiler4.c runtime/runtime.c

echo "Compiling compiler5"
./compiler4 -cv2 compiler/*.slang | sed '/^# /d' > tmp-compiler5.c
gcc -Wno-incompatible-pointer-types -Wno-int-conversion -o compiler5 tmp-compiler5.c runtime/runtime.c

diff tmp-compiler4.c tmp-compiler5.c

echo "Compiling compiler6"
echo "#!/usr/bin/env python" > ${COMPILER6}
./compiler5 compiler/*.slang >> ${COMPILER6}

echo "OK"
