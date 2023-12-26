
# Configuration settings:
BUILDDIR=build

# Variables:
COMPILER_SRCS := $(wildcard compiler/*/*.slang)
COMPILER_SRCS += $(wildcard compiler/*.slang)
COMPILER_SRCS += runtime/std.slang
COMPILER_LIB_SRCS := compiler/utils/strlib.slang compiler/utils/utils.slang compiler/utils/datatypes.slang
BASE_LIB_SRCS := $(wildcard Libs/base/*.slang)
BASE_LIB_SRCS += ${COMPILER_LIB_SRCS}
BASE_LIB_SRCS += runtime/std.slang
TEST_LIB_SRCS := tests/unittest.slang
REGEX_LIB_SRCS := Libs/regex/regex.slang Libs/regex/integersetlib.slang Libs/regex/rangelib.slang
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
TESTS := $(wildcard tests/test_*.slang)
ALL_TEST_RUNS := $(patsubst tests/test_%.slang, run-test-%, $(TESTS))

.PHONY: all check
all: ${BUILDDIR}/c/hello-world.exe ${BUILDDIR}/c/mandel.exe ${BUILDDIR}/regex.exe

check: ${ALL_TEST_RUNS}

# Example to bytecode compilation
all-examples-bc: $(BC_EXAMPLES)

${BUILDDIR}/bc/%.txt: examples/%.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} --backend-bc $< runtime/std.slang > $@


# Example compiled to Python code:
all-examples-python: $(PY_EXAMPLES)

${BUILDDIR}/python/%.py: examples/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} --backend-py -o $@ $< runtime/std.slang

# examples compiled to C code:
all-examples-c: $(C_EXAMPLES)

${BUILDDIR}/%.exe: ${BUILDDIR}/%.c ${BUILDDIR}/runtime.o | ${BUILDDIR}
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

# Unit tests:
.PHONY: run_test_%
run-test-%: ${BUILDDIR}/tests/test_%.exe
	$<

${BUILDDIR}/tests/test_%.c: tests/test_%.slang ${TEST_LIB_SRCS} ${REGEX_LIB_SRCS} ${BASE_LIB_SRCS} ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} --backend-c -o $@ $< ${TEST_LIB_SRCS} ${REGEX_LIB_SRCS} ${BASE_LIB_SRCS}

.PRECIOUS: ${BUILDDIR}/tests/test_%.c

# Libs demos
${BUILDDIR}/regex.c: Libs/regex/main.slang ${REGEX_LIB_SRCS} ${BASE_LIB_SRCS} ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} --backend-c -o $@ Libs/regex/main.slang ${REGEX_LIB_SRCS} ${BASE_LIB_SRCS}

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
	mkdir -p ${BUILDDIR}/tests

${BUILDDIR}/runtime.o: runtime/runtime.c | ${BUILDDIR}
	gcc ${CFLAGS} -c -o $@ $<

.PHONY: clean
clean:
	rm -rf ${BUILDDIR}

.SUFFIXES:
