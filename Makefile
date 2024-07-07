
# Configuration settings:
BUILDDIR=build

# Variables:
BASE_LIB_SRCS := $(wildcard Libs/base/*.slang)
BASE_LIB_SRCS += runtime/std.slang
COMPILER_SRCS := $(wildcard compiler/*/*.slang)
COMPILER_SRCS += $(wildcard compiler/*.slang)
COMPILER_SRCS += ${BASE_LIB_SRCS}
REGEX_LIB_SRCS := $(wildcard Libs/regex/*.slang)
GFX_LIB_SRCS := $(wildcard Libs/gfx/*.slang)
IMAGE_LIB_SRCS := $(wildcard Libs/image/*.slang)
COMPILER1=${BUILDDIR}/tmp-compiler.py
COMPILER2=${BUILDDIR}/tmp-compiler2.py
COMPILER3=${BUILDDIR}/tmp-compiler3.py
COMPILER4=${BUILDDIR}/compiler4
COMPILER5=${BUILDDIR}/compiler5
COMPILER6=${BUILDDIR}/tmp-compiler6.py
SLANGC=python ${COMPILER6}
SLANG_APPS := $(wildcard Apps/*.slang)

CFLAGS=-Wfatal-errors -Werror -Wreturn-type -g
SLANG_EXAMPLES := $(wildcard examples/snippets/*.slang)
WASM_EXAMPLES := $(patsubst examples/snippets/%.slang, build/wasm/%.wasm, $(SLANG_EXAMPLES))
PY_EXAMPLES := $(patsubst examples/snippets/%.slang, build/python/%.py, $(SLANG_EXAMPLES))
C_EXAMPLES := $(patsubst examples/snippets/%.slang, build/c/snippets/%.exe, $(SLANG_EXAMPLES))
C_APPS := $(patsubst Apps/%.slang, build/c/apps/%.exe, $(SLANG_APPS))
BC_EXAMPLES := $(patsubst examples/snippets/%.slang, build/bc/%.txt, $(SLANG_EXAMPLES))
TESTS := $(wildcard tests/test_*.slang)
ALL_TEST_RUNS := $(patsubst tests/test_%.slang, run-test-c-%, $(TESTS))
ALL_TEST_RUNS_PY := $(patsubst tests/test_%.slang, run-test-py-%, $(TESTS))

.PHONY: all check check-py all-examples all-examples-bc all-examples-c all-examples-python
all: ${C_APPS} all-examples
all-examples: all-examples-bc all-examples-c all-examples-python

check: ${ALL_TEST_RUNS}
check-py: ${ALL_TEST_RUNS_PY}

# Example to bytecode compilation
all-examples-bc: $(BC_EXAMPLES)

${BUILDDIR}/bc/%.txt: examples/snippets/%.slang ${COMPILER6} | ${BUILDDIR}/bc
	python ${COMPILER6} --backend-bc $< runtime/std.slang > $@

# Example compiled to Python code:
all-examples-python: $(PY_EXAMPLES)

${BUILDDIR}/python/%.py: examples/snippets/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}/python
	python ${COMPILER6} --backend-py -o $@ $< runtime/std.slang

# examples compiled to C code:
all-examples-c: $(C_EXAMPLES)

.PRECIOUS: ${BUILDDIR}/c/snippets/%.exe ${BUILDDIR}/c/snippets/%.c
${BUILDDIR}/c/snippets/%.exe: ${BUILDDIR}/c/snippets/%.c ${BUILDDIR}/runtime.o | ${BUILDDIR}/c/snippets
	gcc ${CFLAGS} -o $@ $< ${BUILDDIR}/runtime.o -lm

${BUILDDIR}/c/snippets/%.c: examples/snippets/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}/c/snippets
	${SLANGC} --backend-c -o $@ $< runtime/std.slang

# Base lib as DLL:
${BUILDDIR}/c/libbase.c ${BUILDDIR}/c/libbase.json: ${BASE_LIB_SRCS} ${REGEX_LIB_SRCS} ${COMPILER6} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libbase.json -o ${BUILDDIR}/c/libbase.c ${BASE_LIB_SRCS} ${REGEX_LIB_SRCS}

${BUILDDIR}/c/libbase.so: ${BUILDDIR}/c/libbase.c
	gcc ${CFLAGS} -shared -fPIC -o $@ $<

# Base lib as python module
${BUILDDIR}/python/libbase.py ${BUILDDIR}/python/libbase.json: ${BASE_LIB_SRCS} ${REGEX_LIB_SRCS} ${COMPILER6} | ${BUILDDIR}/python
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libbase.json -o ${BUILDDIR}/python/libbase.py ${BASE_LIB_SRCS} ${REGEX_LIB_SRCS}

# linkage-example: ${BUILDDIR}/c/linkage-main.exe
${BUILDDIR}/c/linkage/libfancy.c ${BUILDDIR}/c/linkage/libfancy.json: examples/linkage/fancy.slang ${COMPILER6} | ${BUILDDIR}/c/linkage
	${SLANGC} --backend-c -v --gen-export ${BUILDDIR}/c/linkage/libfancy.json -o ${BUILDDIR}/c/linkage/libfancy.c examples/linkage/fancy.slang runtime/std.slang

${BUILDDIR}/c/linkage/main.c: examples/linkage/main.slang ${BUILDDIR}/c/linkage/libfancy.json ${COMPILER6} | ${BUILDDIR}/c/linkage
	jq '.modules[1].definitions[7]' ${BUILDDIR}/c/linkage/libfancy.json --indent 5
	${SLANGC} --backend-c -v --add-import ${BUILDDIR}/c/linkage/libfancy.json -o $@ examples/linkage/main.slang

${BUILDDIR}/c/linkage/libfancy.so: ${BUILDDIR}/c/linkage/libfancy.c
	gcc ${CFLAGS} -shared -fPIC -o $@ $<

${BUILDDIR}/c/linkage/main.exe: ${BUILDDIR}/c/linkage/main.c ${BUILDDIR}/c/linkage/libfancy.so
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c/linkage -Wl,-rpath=`pwd`/${BUILDDIR}/c/linkage -l:libfancy.so ${BUILDDIR}/runtime.o -lm

linkage: ${BUILDDIR}/c/linkage/main.exe

# Wasm examples:
all-examples-wasm: $(WASM_EXAMPLES)

%.wasm: %.wat
	wat2wasm $< -o $@

.PRECIOUS: ${BUILDDIR}/wasm/%.wat

${BUILDDIR}/wasm/%.wat: examples/snippets/%.slang runtime/std.slang ${COMPILER6} | ${BUILDDIR}/wasm
	${SLANGC} -wasm $< runtime/std.slang | sed '/^# /d' > $@

# Unit tests with C backend:
.PHONY: run-test-c-%
.PRECIOUS: ${BUILDDIR}/tests/test_%.c ${BUILDDIR}/tests/test_%.exe
run-test-c-%: ${BUILDDIR}/tests/test_%.exe
	$<

${BUILDDIR}/tests/test_%.c: tests/test_%.slang ${BUILDDIR}/c/libbase.json ${COMPILER6} | ${BUILDDIR}/tests
	${SLANGC} --backend-c -o $@ $< --add-import ${BUILDDIR}/c/libbase.json

${BUILDDIR}/tests/test_%.exe: ${BUILDDIR}/tests/test_%.c ${BUILDDIR}/c/libbase.so
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c -Wl,-rpath=`pwd`/${BUILDDIR}/c -l:libbase.so ${BUILDDIR}/runtime.o -lm

# Unit tests with python backend:
.PHONY: run-test-py-%
.PRECIOUS: ${BUILDDIR}/python/test_%.py
run-test-py-%: ${BUILDDIR}/python/test_%.py ${BUILDDIR}/python/runtime.py
	python $<

${BUILDDIR}/python/runtime.py: runtime/runtime.py | ${BUILDDIR}/python
	cp $< $@

${BUILDDIR}/python/test_%.py: tests/test_%.slang ${BUILDDIR}/python/libbase.json ${COMPILER6} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ $< --add-import ${BUILDDIR}/python/libbase.json

# Apps
${BUILDDIR}/c/apps/%.c: Apps/%.slang ${GFX_LIB_SRCS} ${IMAGE_LIB_SRCS} ${REGEX_LIB_SRCS} ${BASE_LIB_SRCS} ${COMPILER6} | ${BUILDDIR}/c/apps
	${SLANGC} --backend-c -o $@ $< ${GFX_LIB_SRCS} ${IMAGE_LIB_SRCS} ${REGEX_LIB_SRCS} ${BASE_LIB_SRCS}

# Bootstrap sequence:
${COMPILER1}: | ${COMPILER_SRCS} compiler1/*.py ${BUILDDIR}
	python bootstrap.py

${BUILDDIR}/runtime.py: runtime/runtime.py | ${BUILDDIR}
	cp $< $@

${COMPILER2}: ${BUILDDIR}/runtime.py | ${COMPILER_SRCS} ${BUILDDIR}/tmp-compiler.py ${BUILDDIR}
	python ${COMPILER1} --backend-py -o ${COMPILER2} ${COMPILER_SRCS}

${COMPILER3}: | ${COMPILER_SRCS} ${COMPILER2} ${BUILDDIR}
	python ${COMPILER2} --backend-py -o ${COMPILER3} ${COMPILER_SRCS}

${BUILDDIR}/tmp-compiler4.c: | ${COMPILER_SRCS} ${BUILDDIR} ${COMPILER3}
	python ${COMPILER3} --backend-c -o ${BUILDDIR}/tmp-compiler4.c ${COMPILER_SRCS}

${COMPILER4}: ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/runtime.o
	gcc ${CFLAGS} -o ${COMPILER4} ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/runtime.o -lm

${BUILDDIR}/tmp-compiler5.c: | ${COMPILER_SRCS} ${BUILDDIR} ${COMPILER4}
	./${COMPILER4} --backend-c -o ${BUILDDIR}/tmp-compiler5.c ${COMPILER_SRCS}

${COMPILER5}: ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/runtime.o | ${BUILDDIR}
	gcc ${CFLAGS} -o ${COMPILER5} ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/runtime.o -lm

${COMPILER6}: ${COMPILER_SRCS} | ${BUILDDIR} ${COMPILER5}
	./${COMPILER5} --backend-py -o ${COMPILER6} ${COMPILER_SRCS}

${BUILDDIR}/compiler.wat: ${COMPILER_SRCS} ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm ${COMPILER_SRCS}

# Helper targets:
${BUILDDIR}:
	mkdir -p ${BUILDDIR}

${BUILDDIR}/c:
	mkdir -p ${BUILDDIR}/c

${BUILDDIR}/c/snippets:
	mkdir -p ${BUILDDIR}/c/snippets

${BUILDDIR}/c/linkage:
	mkdir -p ${BUILDDIR}/c/linkage

${BUILDDIR}/python:
	mkdir -p ${BUILDDIR}/python

${BUILDDIR}/wasm:
	mkdir -p ${BUILDDIR}/wasm

${BUILDDIR}/bc:
	mkdir -p ${BUILDDIR}/bc

${BUILDDIR}/tests:
	mkdir -p ${BUILDDIR}/tests

${BUILDDIR}/c/apps:
	mkdir -p ${BUILDDIR}/c/apps

${BUILDDIR}/runtime.o: runtime/runtime.c | ${BUILDDIR}
	gcc ${CFLAGS} -c -o $@ $<

.PHONY: clean
clean:
	rm -rf ${BUILDDIR}

.SUFFIXES:
