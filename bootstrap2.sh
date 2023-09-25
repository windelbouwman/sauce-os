#!/bin/bash

set -eu

COMPILER1="tmp-compiler.py"
COMPILER2="tmp-compiler2.py"
COMPILER3="tmp-compiler3.py"

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

echo "OK"
