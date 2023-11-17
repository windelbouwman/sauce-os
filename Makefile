
# Configuration settings:
BUILDDIR=build

# Variables:
COMPILER_SRCS := $(wildcard compiler/*/*.slang)
COMPILER_SRCS += $(wildcard compiler/*.slang)
COMPILER1=${BUILDDIR}/tmp-compiler.py
COMPILER2=${BUILDDIR}/tmp-compiler2.py
COMPILER3=${BUILDDIR}/tmp-compiler3.py
COMPILER4=${BUILDDIR}/compiler4
COMPILER5=${BUILDDIR}/compiler5
COMPILER6=${BUILDDIR}/tmp-compiler6.py


all: hello-world

# Compile hello world example:
hello-world: examples/hello-world.slang ${COMPILER5}
	./${COMPILER5} -cv2 examples/hello-world.slang

loops: ${COMPILER3} examples/loops.slang
	python ${COMPILER3} -bc examples/loops.slang

mandel: ${COMPILER3} examples/mandel.slang
	python ${COMPILER3} -bc examples/mandel.slang

structs-passing: ${COMPILER3} examples/structs-passing.slang
	python ${COMPILER3} -bc examples/structs-passing.slang

enum-case: ${COMPILER3} examples/enum_case.slang
	python ${COMPILER3} -bc examples/enum_case.slang

classy: ${COMPILER3} examples/classy.slang
	python ${COMPILER3} -bc examples/classy.slang

generic-enum: ${COMPILER3} examples/generic-enum.slang
	python ${COMPILER3} -cv2 examples/generic-enum.slang

exceptionally: ${COMPILER3} examples/exceptionally.slang
	python ${COMPILER3} -cv2 examples/exceptionally.slang

func_ptr: ${COMPILER3} examples/func_ptr.slang
	python ${COMPILER3} -cv2 examples/func_ptr.slang

list-generic-oo: compiler5 examples/list-generic-oo.slang
	./compiler5 -cv2 examples/list-generic-oo.slang | sed '/^# /d' > tmp-list-generic-oo.c
	gcc -o list-generic-oo tmp-list-generic-oo.c runtime/runtime.c

generics2: ${COMPILER3} runtime/runtime.c examples/generics2.slang
	python ${COMPILER3} -cv2 examples/generics2.slang | sed '/^# /d' > generics2.c
	gcc generics2.c runtime/runtime.c

# Wasm examples:
examples-wasm: hello-world-wasm struct-passing-wasm

hello-world-wasm: ${BUILDDIR}/wasm/hello-world.wasm

${BUILDDIR}/wasm/hello-world.wasm: examples/hello-world.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm examples/hello-world.slang | sed '/^# /d' > ${BUILDDIR}/wasm/hello-world.wat
	wat2wasm ${BUILDDIR}/wasm/hello-world.wat -o ${BUILDDIR}/wasm/hello-world.wasm

struct-passing-wasm: ${BUILDDIR}/wasm/struct-passing.wasm

${BUILDDIR}/wasm/struct-passing.wasm: examples/structs-passing.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm examples/structs-passing.slang | sed '/^# /d' > ${BUILDDIR}/wasm/struct-passing.wat
	wat2wasm ${BUILDDIR}/wasm/struct-passing.wat -o ${BUILDDIR}/wasm/struct-passing.wasm

# Bootstrap sequence:

${BUILDDIR}/tmp-compiler.py: ${COMPILER_SRCS} | ${BUILDDIR}
	python bootstrap.py

${COMPILER2}: ${COMPILER_SRCS} | ${BUILDDIR}/tmp-compiler.py ${BUILDDIR}
	echo "#!/usr/bin/env python" > ${COMPILER2}
	python ${COMPILER1} ${COMPILER_SRCS} >> ${COMPILER2}
	chmod +x ${COMPILER2}

${COMPILER3}: ${COMPILER_SRCS} | ${BUILDDIR}/tmp-compiler2.py ${BUILDDIR}
	echo "#!/usr/bin/env python" > ${COMPILER3}
	python ${COMPILER2} ${COMPILER_SRCS} >> ${COMPILER3}
	chmod +x ${COMPILER3}

${BUILDDIR}/tmp-compiler4.c: ${COMPILER_SRCS} | ${BUILDDIR} ${COMPILER3}
	python ${COMPILER3} -cv2 ${COMPILER_SRCS} | sed '/^# /d' > ${BUILDDIR}/tmp-compiler4.c

${COMPILER4}: ${BUILDDIR}/tmp-compiler4.c runtime/runtime.c
	gcc -o ${COMPILER4} ${BUILDDIR}/tmp-compiler4.c runtime/runtime.c

${BUILDDIR}/tmp-compiler5.c: ${COMPILER_SRCS} | ${BUILDDIR} ${COMPILER4}
	./${COMPILER4} -cv2 ${COMPILER_SRCS} | sed '/^# /d' > ${BUILDDIR}/tmp-compiler5.c

${COMPILER5}: ${BUILDDIR}/tmp-compiler5.c runtime/runtime.c | ${BUILDDIR}
	gcc -o ${COMPILER5} ${BUILDDIR}/tmp-compiler5.c runtime/runtime.c

${COMPILER6}: ${COMPILER_SRCS} | ${BUILDDIR}  # ${COMPILER5}
	echo "#!/usr/bin/env python" > ${COMPILER6}
	./${COMPILER5} ${COMPILER_SRCS} >> ${COMPILER6}

build/compiler.wat: ${COMPILER_SRCS} ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm ${COMPILER_SRCS}

# Helper targets:
${BUILDDIR}:
	mkdir -p ${BUILDDIR}
	mkdir -p ${BUILDDIR}/wasm
	mkdir -p ${BUILDDIR}/python

clean:
	rm -rf ${BUILDDIR}

