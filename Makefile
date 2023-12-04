
# Configuration settings:
BUILDDIR=build

# Variables:
COMPILER_SRCS := $(wildcard compiler/*/*.slang)
COMPILER_SRCS += $(wildcard compiler/*.slang)
COMPILER_SRCS += runtime/std.slang
COMPILER1=${BUILDDIR}/tmp-compiler.py
COMPILER2=${BUILDDIR}/tmp-compiler2.py
COMPILER3=${BUILDDIR}/tmp-compiler3.py
COMPILER4=${BUILDDIR}/compiler4
COMPILER5=${BUILDDIR}/compiler5
COMPILER6=${BUILDDIR}/tmp-compiler6.py

CFLAGS=-Wfatal-errors -Werror -Wreturn-type
SLANG_EXAMPLES := $(wildcard examples/*.slang)
WASM_EXAMPLES := $(patsubst examples/%.slang, build/wasm/%.wasm, $(SLANG_EXAMPLES))
PY_EXAMPLES := $(patsubst examples/%.slang, build/python/%.py, $(SLANG_EXAMPLES))
C_EXAMPLES := $(patsubst examples/%.slang, build/c/%.exe, $(SLANG_EXAMPLES))
BC_EXAMPLES := $(patsubst examples/%.slang, build/bc/%.txt, $(SLANG_EXAMPLES))


all: build/c/hello-world.exe build/c/mandel.exe


# Example to bytecode compilation
all-examples-bc: $(BC_EXAMPLES)

${BUILDDIR}/bc/%.txt: examples/%.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -bc $< > $@


# Example compiled to Python code:
all-examples-python: $(PY_EXAMPLES)

${BUILDDIR}/python/%.py: examples/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} --backend-py -o $@ $< runtime/std.slang


# examples compiled to C code:
all-examples-c: $(C_EXAMPLES)

${BUILDDIR}/c/%.exe: ${BUILDDIR}/c/%.c ${BUILDDIR}/runtime.o | ${BUILDDIR}
	gcc ${CFLAGS} -o $@ $< ${BUILDDIR}/runtime.o

.PRECIOUS: ${BUILDDIR}/c/%.c

${BUILDDIR}/c/%.c: examples/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} --backend-c -o $@ $< runtime/std.slang


# Wasm examples:
all-examples-wasm: $(WASM_EXAMPLES)

%.wasm: %.wat
	wat2wasm $< -o $@

.PRECIOUS: ${BUILDDIR}/wasm/%.wat

${BUILDDIR}/wasm/%.wat: examples/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm $< runtime/std.slang | sed '/^# /d' > $@


# Bootstrap sequence:
${BUILDDIR}/tmp-compiler.py: ${COMPILER_SRCS} compiler1/*.py | ${BUILDDIR}
	python bootstrap.py

${COMPILER2}: ${COMPILER_SRCS} ${BUILDDIR}/tmp-compiler.py | ${BUILDDIR}
	python ${COMPILER1} --backend-py -o ${COMPILER2} ${COMPILER_SRCS}

${COMPILER3}: ${COMPILER_SRCS} | ${BUILDDIR}/tmp-compiler2.py ${BUILDDIR}
	python ${COMPILER2} --backend-py -o ${COMPILER3} ${COMPILER_SRCS}

${BUILDDIR}/tmp-compiler4.c: ${COMPILER_SRCS} | ${BUILDDIR} ${COMPILER3}
	python ${COMPILER3} --backend-c -o ${BUILDDIR}/tmp-compiler4.c ${COMPILER_SRCS}

${COMPILER4}: ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/runtime.o
	gcc ${CFLAGS} -o ${COMPILER4} ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/runtime.o

${BUILDDIR}/tmp-compiler5.c: ${COMPILER_SRCS} | ${BUILDDIR} # ${COMPILER4}
	./${COMPILER4} --backend-c -o ${BUILDDIR}/tmp-compiler5.c ${COMPILER_SRCS}

${COMPILER5}: ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/runtime.o | ${BUILDDIR}
	gcc ${CFLAGS} -o ${COMPILER5} ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/runtime.o

${COMPILER6}: ${COMPILER_SRCS} | ${BUILDDIR} #  ${COMPILER5}
	./${COMPILER5} --backend-py -o ${COMPILER6} ${COMPILER_SRCS}

${BUILDDIR}/compiler.wat: ${COMPILER_SRCS} ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm ${COMPILER_SRCS}

# Helper targets:
${BUILDDIR}:
	mkdir -p ${BUILDDIR}
	mkdir -p ${BUILDDIR}/wasm
	mkdir -p ${BUILDDIR}/python
	mkdir -p ${BUILDDIR}/c
	mkdir -p ${BUILDDIR}/bc

${BUILDDIR}/runtime.o: runtime/runtime.c | ${BUILDDIR}
	gcc ${CFLAGS} -c -o $@ $<

clean:
	rm -rf ${BUILDDIR}

.SUFFIXES:
