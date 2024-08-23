
# Configuration settings:
BUILDDIR=build

# Variables:
BASE_LIB_SRCS := $(wildcard Libs/base/*.slang)
BASE_LIB_SRCS += runtime/std.slang
COMPILER_LIB_SRCS := $(wildcard Libs/compiler/*.slang)
COMPILER_LIB_SRCS += $(wildcard Libs/compiler/*/*.slang)
COMPILER_SRCS := $(wildcard compiler/main.slang)
REGEX_LIB_SRCS := $(wildcard Libs/regex/*.slang)
GFX_LIB_SRCS := $(wildcard Libs/gfx/*.slang)
IMAGE_LIB_SRCS := $(wildcard Libs/image/*.slang)
WEB_LIB_SRCS := $(wildcard Libs/web/*.slang)
COMPILER1=${BUILDDIR}/tmp-compiler.py
COMPILER2=${BUILDDIR}/tmp-compiler2.py
COMPILER3=${BUILDDIR}/tmp-compiler3.py
COMPILER4=${BUILDDIR}/compiler4
COMPILER5=${BUILDDIR}/compiler5
COMPILER6=${BUILDDIR}/tmp-compiler6.py
#SLANGC=python ${COMPILER3}
#SLANGC_DEPS=${COMPILER3}
SLANGC=./${COMPILER5}
SLANGC_DEPS=${COMPILER5}
SLANG_APPS := $(wildcard Apps/*.slang)

CFLAGS=-Werror -Wreturn-type -g -Iruntime
SLANG_EXAMPLES := $(wildcard examples/snippets/*.slang)
SLANG2_EXAMPLES := $(patsubst examples/snippets/%.slang, build/slang/%.slang, $(SLANG_EXAMPLES))
WASM_EXAMPLES := $(patsubst examples/snippets/%.slang, build/wasm/%.wasm, $(SLANG_EXAMPLES))
PY_EXAMPLES := $(patsubst examples/snippets/%.slang, build/python/%.py, $(SLANG_EXAMPLES))
C_EXAMPLES := $(patsubst examples/snippets/%.slang, build/c/snippets/%.exe, $(SLANG_EXAMPLES))
C_APPS := $(patsubst Apps/%.slang, build/c/apps/%.exe, $(SLANG_APPS))
BC_EXAMPLES := $(patsubst examples/snippets/%.slang, build/bc/%.txt, $(SLANG_EXAMPLES))
TESTS := $(wildcard tests/test_*.slang)
ALL_TEST_RUNS := $(patsubst tests/test_%.slang, run-test-c-%, $(TESTS))
ALL_TEST_RUNS_PY := $(patsubst tests/test_%.slang, run-test-py-%, $(TESTS))

.PHONY: all check check-py all-examples all-examples-bc all-examples-c all-examples-python test pytest-exes
all: ${C_APPS} all-examples
all-examples: all-examples-bc all-examples-c all-examples-python all-examples-slang2
test: pytest-compiler pytest-compiler1 check check-py

check: ${ALL_TEST_RUNS}
check-py: ${ALL_TEST_RUNS_PY}

# Profiling
profile: ${COMPILER5} | ${BUILDDIR}
	valgrind --tool=callgrind --callgrind-out-file=build/callgrind.out ./${COMPILER5} --backend-null ${BASE_LIB_SRCS}
	kcachegrind build/callgrind.out

pytest-compiler1:
	pytest -v test_compiler1.py

pytest-compiler: $(C_EXAMPLES)
	pytest -vv test_compiler.py

# Example to bytecode compilation
all-examples-bc: $(BC_EXAMPLES)

${BUILDDIR}/bc/%.txt: examples/snippets/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/bc
	${SLANGC} --backend-bc $< runtime/std.slang > $@

# Example compiled to slang-code!
all-examples-slang2: $(SLANG2_EXAMPLES)

${BUILDDIR}/slang/%.slang: examples/snippets/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/slang
	${SLANGC} -o $@ --backend-slang $< runtime/std.slang
#	${SLANGC} --backend-null $@  # Validate slang code

# Example compiled to Python code:
all-examples-python: $(PY_EXAMPLES)

${BUILDDIR}/python/%.py: examples/snippets/%.slang runtime/std.slang ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ $< runtime/std.slang

# examples compiled to C code:
all-examples-c: $(C_EXAMPLES)

.PRECIOUS: ${BUILDDIR}/c/snippets/%.exe ${BUILDDIR}/c/snippets/%.c
${BUILDDIR}/c/snippets/%.exe: ${BUILDDIR}/c/snippets/%.c ${BUILDDIR}/slangrt.o | ${BUILDDIR}/c/snippets
	gcc ${CFLAGS} -o $@ $< ${BUILDDIR}/slangrt.o -lm

${BUILDDIR}/c/snippets/%.c: examples/snippets/%.slang runtime/std.slang ${SLANGC_DEPS} | ${BUILDDIR}/c/snippets
	${SLANGC} --backend-c -o $@ $< runtime/std.slang

# Base lib as DLL:
${BUILDDIR}/c/libbase.c ${BUILDDIR}/c/libbase.json: ${BASE_LIB_SRCS} ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libbase.json -o ${BUILDDIR}/c/libbase.c ${BASE_LIB_SRCS}

${BUILDDIR}/c/libregex.c ${BUILDDIR}/c/libregex.json: ${REGEX_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libregex.json -o ${BUILDDIR}/c/libregex.c --add-import ${BUILDDIR}/c/libbase.json ${REGEX_LIB_SRCS}

${BUILDDIR}/c/libimage.c ${BUILDDIR}/c/libimage.json: ${IMAGE_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libimage.json -o ${BUILDDIR}/c/libimage.c --add-import ${BUILDDIR}/c/libbase.json ${IMAGE_LIB_SRCS}

${BUILDDIR}/c/libgfx.c ${BUILDDIR}/c/libgfx.json: ${GFX_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libgfx.json -o ${BUILDDIR}/c/libgfx.c --add-import ${BUILDDIR}/c/libbase.json ${GFX_LIB_SRCS}

${BUILDDIR}/c/libweb.c ${BUILDDIR}/c/libweb.json: ${WEB_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libweb.json -o ${BUILDDIR}/c/libweb.c --add-import ${BUILDDIR}/c/libbase.json ${WEB_LIB_SRCS}

${BUILDDIR}/c/libcompiler.c ${BUILDDIR}/c/libcompiler.json: ${COMPILER_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c --gen-export ${BUILDDIR}/c/libcompiler.json -o ${BUILDDIR}/c/libcompiler.c --add-import ${BUILDDIR}/c/libbase.json ${COMPILER_LIB_SRCS}

.PRECIOUS: ${BUILDDIR}/c/lib%.so
${BUILDDIR}/c/lib%.so: ${BUILDDIR}/c/lib%.c
	gcc ${CFLAGS} -shared -fPIC -o $@ $<

# Base lib as python module
${BUILDDIR}/python/libbase.py ${BUILDDIR}/python/libbase.json: ${BASE_LIB_SRCS} ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libbase.json -o ${BUILDDIR}/python/libbase.py ${BASE_LIB_SRCS}

${BUILDDIR}/python/libregex.py ${BUILDDIR}/python/libregex.json: ${REGEX_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libregex.json -o ${BUILDDIR}/python/libregex.py --add-import ${BUILDDIR}/python/libbase.json ${REGEX_LIB_SRCS}

${BUILDDIR}/python/libimage.py ${BUILDDIR}/python/libimage.json: ${IMAGE_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libimage.json -o ${BUILDDIR}/python/libimage.py --add-import ${BUILDDIR}/python/libbase.json ${IMAGE_LIB_SRCS}

${BUILDDIR}/python/libcompiler.py ${BUILDDIR}/python/libcompiler.json: ${COMPILER_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libcompiler.json -o ${BUILDDIR}/python/libcompiler.py --add-import ${BUILDDIR}/python/libbase.json ${COMPILER_LIB_SRCS}

# linkage-example: ${BUILDDIR}/c/linkage-main.exe
${BUILDDIR}/c/linkage/libfubar.c ${BUILDDIR}/c/linkage/libfubar.json: examples/linkage/fubar.slang ${SLANGC_DEPS} | ${BUILDDIR}/c/linkage
	${SLANGC} --backend-c -v --gen-export ${BUILDDIR}/c/linkage/libfubar.json -o ${BUILDDIR}/c/linkage/libfubar.c examples/linkage/fubar.slang runtime/std.slang

${BUILDDIR}/c/linkage/libfancy.c ${BUILDDIR}/c/linkage/libfancy.json: examples/linkage/fancy.slang ${BUILDDIR}/c/linkage/libfubar.json ${SLANGC_DEPS} | ${BUILDDIR}/c/linkage
	${SLANGC} --backend-c -v --gen-export ${BUILDDIR}/c/linkage/libfancy.json -o ${BUILDDIR}/c/linkage/libfancy.c --add-import ${BUILDDIR}/c/linkage/libfubar.json examples/linkage/fancy.slang

${BUILDDIR}/c/linkage/main.c: examples/linkage/main.slang ${BUILDDIR}/c/linkage/libfancy.json ${SLANGC_DEPS} | ${BUILDDIR}/c/linkage
	jq '.' ${BUILDDIR}/c/linkage/libfancy.json --indent 5
	${SLANGC} --backend-c -v --add-import ${BUILDDIR}/c/linkage/libfancy.json --add-import ${BUILDDIR}/c/linkage/libfubar.json -o $@ examples/linkage/main.slang

${BUILDDIR}/c/linkage/libfancy.so: ${BUILDDIR}/c/linkage/libfancy.c
	gcc ${CFLAGS} -shared -fPIC -o $@ $<

${BUILDDIR}/c/linkage/main.exe: ${BUILDDIR}/c/linkage/main.c ${BUILDDIR}/c/linkage/libfancy.so ${BUILDDIR}/slangrt.o
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c/linkage -Wl,-rpath=`pwd`/${BUILDDIR}/c/linkage -l:libfancy.so ${BUILDDIR}/slangrt.o -lm

linkage: ${BUILDDIR}/c/linkage/main.exe

# Wasm examples:
all-examples-wasm: $(WASM_EXAMPLES)

%.wasm: %.wat
	wat2wasm $< -o $@

.PRECIOUS: ${BUILDDIR}/wasm/%.wat

${BUILDDIR}/wasm/%.wat: examples/snippets/%.slang runtime/std.slang ${SLANGC_DEPS} | ${BUILDDIR}/wasm
	${SLANGC} -wasm $< runtime/std.slang | sed '/^# /d' > $@

# Unit tests with C backend:
.PHONY: run-test-c-%
.PRECIOUS: ${BUILDDIR}/tests/test_%.c ${BUILDDIR}/tests/test_%.exe
run-test-c-%: ${BUILDDIR}/tests/test_%.exe
	$<

${BUILDDIR}/tests/test_%.c: tests/test_%.slang ${BUILDDIR}/c/libcompiler.json ${BUILDDIR}/c/libimage.json ${BUILDDIR}/c/libbase.json ${BUILDDIR}/c/libregex.json ${SLANGC_DEPS} | ${BUILDDIR}/tests
	${SLANGC} --backend-c -o $@ $< --add-import ${BUILDDIR}/c/libcompiler.json --add-import ${BUILDDIR}/c/libimage.json --add-import ${BUILDDIR}/c/libbase.json --add-import ${BUILDDIR}/c/libregex.json

${BUILDDIR}/tests/test_%.exe: ${BUILDDIR}/tests/test_%.c ${BUILDDIR}/c/libcompiler.so ${BUILDDIR}/c/libimage.so ${BUILDDIR}/c/libbase.so ${BUILDDIR}/c/libregex.so ${BUILDDIR}/slangrt.o
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c -Wl,-rpath=`pwd`/${BUILDDIR}/c -l:libcompiler.so -l:libimage.so -l:libregex.so -l:libbase.so ${BUILDDIR}/slangrt.o -lm

# Unit tests with python backend:
.PHONY: run-test-py-%
.PRECIOUS: ${BUILDDIR}/python/test_%.py
run-test-py-%: ${BUILDDIR}/python/test_%.py ${BUILDDIR}/python/slangrt.py
	python $<

${BUILDDIR}/python/slangrt.py: runtime/slangrt.py | ${BUILDDIR}/python
	cp $< $@

${BUILDDIR}/python/test_%.py: tests/test_%.slang ${BUILDDIR}/python/libcompiler.json ${BUILDDIR}/python/libimage.json ${BUILDDIR}/python/libbase.json ${BUILDDIR}/python/libregex.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ --add-import ${BUILDDIR}/python/libcompiler.json --add-import ${BUILDDIR}/python/libimage.json --add-import ${BUILDDIR}/python/libbase.json --add-import ${BUILDDIR}/python/libregex.json $<

# Apps
.PRECIOUS: ${BUILDDIR}/c/apps/%.c
${BUILDDIR}/c/apps/%.c: Apps/%.slang ${BUILDDIR}/c/libbase.json ${BUILDDIR}/c/libregex.json ${BUILDDIR}/c/libimage.json ${BUILDDIR}/c/libgfx.json ${BUILDDIR}/c/libcompiler.json ${SLANGC_DEPS} | ${BUILDDIR}/c/apps
	${SLANGC} --backend-c -o $@ $< --add-import ${BUILDDIR}/c/libbase.json --add-import ${BUILDDIR}/c/libregex.json --add-import ${BUILDDIR}/c/libimage.json --add-import ${BUILDDIR}/c/libgfx.json --add-import ${BUILDDIR}/c/libcompiler.json

${BUILDDIR}/c/apps/%.exe: ${BUILDDIR}/c/apps/%.c ${BUILDDIR}/c/libbase.so ${BUILDDIR}/c/libregex.so ${BUILDDIR}/c/libimage.so ${BUILDDIR}/c/libgfx.so ${BUILDDIR}/c/libcompiler.so ${BUILDDIR}/slangrt.o
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c -Wl,-rpath=`pwd`/${BUILDDIR}/c -l:libcompiler.so -l:libimage.so -l:libgfx.so -l:libregex.so -l:libbase.so ${BUILDDIR}/slangrt.o -lm

# Bootstrap sequence:
${COMPILER1}: ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} | ${BASE_LIB_SRCS} compiler1/*.py ${BUILDDIR}
	python bootstrap.py

${BUILDDIR}/slangrt.py: runtime/slangrt.py | ${BUILDDIR}
	cp $< $@

${COMPILER2}: ${BUILDDIR}/slangrt.py ${COMPILER1} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} | ${BASE_LIB_SRCS} ${BUILDDIR}
	python ${COMPILER1} --backend-py -o ${COMPILER2} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER3}: ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} | ${BASE_LIB_SRCS} ${BUILDDIR} ${COMPILER2}
	python ${COMPILER2} --backend-py -o ${COMPILER3} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${BUILDDIR}/tmp-compiler4.c: ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} | ${BASE_LIB_SRCS} ${BUILDDIR} ${COMPILER3}
	python ${COMPILER3} --backend-c -o ${BUILDDIR}/tmp-compiler4.c ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER4}: ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/slangrt.o
	gcc ${CFLAGS} -o ${COMPILER4} ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/slangrt.o -lm

${BUILDDIR}/tmp-compiler5.c: ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} | ${BASE_LIB_SRCS} ${BUILDDIR} ${COMPILER4}
	./${COMPILER4} --backend-c -o ${BUILDDIR}/tmp-compiler5.c ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER5}: ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/slangrt.o | ${BUILDDIR}
	gcc ${CFLAGS} -o ${COMPILER5} ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/slangrt.o -lm

${COMPILER6}: ${COMPILER_SRCS} ${BASE_LIB_SRCS} ${COMPILER5} | ${BUILDDIR}
	./${COMPILER5} --backend-py -o ${COMPILER6} ${COMPILER_SRCS} ${BASE_LIB_SRCS}

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

${BUILDDIR}/slang:
	mkdir -p ${BUILDDIR}/slang

${BUILDDIR}/wasm:
	mkdir -p ${BUILDDIR}/wasm

${BUILDDIR}/bc:
	mkdir -p ${BUILDDIR}/bc

${BUILDDIR}/tests:
	mkdir -p ${BUILDDIR}/tests

${BUILDDIR}/c/apps:
	mkdir -p ${BUILDDIR}/c/apps

${BUILDDIR}/slangrt.o: runtime/slangrt.c | ${BUILDDIR}
	gcc ${CFLAGS} -c -o $@ $<

.PHONY: clean
clean:
	rm -rf ${BUILDDIR}

.SUFFIXES:
