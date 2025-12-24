
# Configuration settings:
BUILDDIR=build

# Variables:
BASE_LIB_SRCS := $(wildcard Libs/base/*.slang)
BASE_LIB_SRCS += runtime/std.slang
COMPILER_LIB_SRCS := $(wildcard Libs/compiler/*.slang)
COMPILER_LIB_SRCS += $(wildcard Libs/compiler/*/*.slang)
COMPILER_SRCS := $(wildcard compiler/main.slang)
GFX_LIB_SRCS := $(wildcard Libs/gfx/*.slang)
SCIENCE_LIB_SRCS := $(wildcard Libs/science/*.slang)
IMAGE_LIB_SRCS := $(wildcard Libs/image/*.slang)
WEB_LIB_SRCS := $(wildcard Libs/web/*.slang)
COMPILER1=${BUILDDIR}/tmp-compiler.py
COMPILER2=${BUILDDIR}/tmp-compiler2.py
COMPILER3=${BUILDDIR}/tmp-compiler3.py
COMPILER4=${BUILDDIR}/compiler4
COMPILER5=${BUILDDIR}/compiler5
COMPILER6=${BUILDDIR}/tmp-compiler6.py
COMPILER7=${BUILDDIR}/tmp-compiler7.py
#SLANGC=python ${COMPILER3}
#SLANGC_DEPS=${COMPILER3}
SLANGC=./${COMPILER5}
SLANGC_DEPS=${COMPILER5}
SLANG_APPS := $(wildcard Apps/*.slang)
AOC_APPS := $(wildcard examples/aoc/*/main.slang)

CFLAGS=-Werror -Wfatal-errors -Wreturn-type -g -Iruntime -rdynamic
SLANG_EXAMPLES := $(wildcard examples/snippets/*.slang)
SLANG2_EXAMPLES := $(patsubst examples/snippets/%.slang, build/slang/%.slang, $(SLANG_EXAMPLES))
SLANG3_EXAMPLES := $(patsubst examples/snippets/%.slang, build/slang3/%.slang, $(SLANG_EXAMPLES))
WASM_EXAMPLES := $(patsubst examples/snippets/%.slang, build/wasm/%.wasm, $(SLANG_EXAMPLES))
PY_EXAMPLES := $(patsubst examples/snippets/%.slang, build/python/snippet-%.py, $(SLANG_EXAMPLES))
PY_APPS := $(patsubst Apps/%.slang, build/python/app-%.py, $(SLANG_APPS))
PY_AOC := $(patsubst examples/aoc/%/main.slang, build/python/aoc-%.py, $(AOC_APPS))
C_EXAMPLES := $(patsubst examples/snippets/%.slang, build/c/snippets/%.exe, $(SLANG_EXAMPLES))
C_EXAMPLES_2 := $(patsubst examples/snippets/%.slang, build/c/snippets2/%.exe, $(SLANG_EXAMPLES))
X86_EXAMPLES := $(patsubst examples/snippets/%.slang, build/x86/snippet_%.exe, $(SLANG_EXAMPLES))
X86_AOC := $(patsubst examples/aoc/%/main.slang, build/x86/aoc_%.exe, $(AOC_APPS))
C_APPS := $(patsubst Apps/%.slang, build/c/apps/%.exe, $(SLANG_APPS))
BC_EXAMPLES := $(patsubst examples/snippets/%.slang, build/bc/%.txt, $(SLANG_EXAMPLES))
TESTS := $(wildcard tests/test_*.slang)
ALL_TEST_RUNS := $(patsubst tests/test_%.slang, run-test-c-%, $(TESTS))
ALL_TEST_RUNS_PY := $(patsubst tests/test_%.slang, run-test-py-%, $(TESTS))
ALL_TEST_RUNS_X86 := $(patsubst tests/test_%.slang, run-test-x86-%, $(TESTS))
X86_TESTS := $(patsubst tests/test_%.slang, build/x86/test_%.exe, $(TESTS))

.PHONY: all check check-py all-examples test pytest-exes
all: ${C_APPS} ${PY_APPS} all-examples aoc
all-examples: all-examples-bc all-examples-c all-examples-python all-examples-slang all-examples-x86
test: pytest-compiler pytest-compiler1 check check-py check-x86

aoc: ${PY_AOC} ${X86_AOC}
check: ${ALL_TEST_RUNS}
check-py: ${ALL_TEST_RUNS_PY}
check-x86: ${ALL_TEST_RUNS_X86}

# Profiling
profile: ${COMPILER5} | ${BUILDDIR}
	valgrind --tool=callgrind --callgrind-out-file=build/callgrind.out ./${COMPILER5} --backend-c-v2 ${BASE_LIB_SRCS}
	kcachegrind build/callgrind.out

profile2: ${BUILDDIR}/c/apps/write_image.exe | ${BUILDDIR}
	valgrind --tool=callgrind --callgrind-out-file=build/callgrind.out ${BUILDDIR}/c/apps/write_image.exe weather-map.gif build/tmp.qoi
	kcachegrind build/callgrind.out

profile3: ${COMPILER5} | ${BUILDDIR}
	valgrind --tool=callgrind --callgrind-out-file=build/callgrind.out ./${COMPILER5} --backend-c -o build/c/apps/write_image.c Apps/write_image.slang --add-import build/c/libbase.json --add-import build/c/libimage.json --add-import build/c/libscience.json --add-import build/c/libgfx.json --add-import build/c/libcompiler.json --add-import build/c/libweb.json
	kcachegrind build/callgrind.out

profile4: ${COMPILER5} | ${BUILDDIR}
	valgrind --tool=callgrind --callgrind-out-file=build/callgrind.out ./${COMPILER5} --backend-null examples/snippets/vtable.slang runtime/std.slang
	kcachegrind build/callgrind.out

profile5: ${COMPILER5} | ${BUILDDIR}
	valgrind --tool=callgrind --callgrind-out-file=build/callgrind.out ./${COMPILER5} --backend-x86 -v ${BASE_LIB_SRCS} -o ${BUILDDIR}/x86/libbase_profile.o
	kcachegrind build/callgrind.out

leakcheck: ${COMPILER5} | ${BUILDDIR}
	valgrind ./${COMPILER5} --backend-null ${BASE_LIB_SRCS}

.PHONY: benchmark
benchmark: ${COMPILER5} | ${BUILDDIR}
	hyperfine './${COMPILER5} --backend-x86 -v ${BASE_LIB_SRCS} -o ${BUILDDIR}/x86/libbase_benchmark.o'

pytest-compiler1:
	pytest -v test_compiler1.py

pytest-compiler: all-examples-c all-examples-python all-examples-x86 aoc
	pytest -vv test_compiler.py

# Example to bytecode compilation
.PHONY: all-examples-bc
all-examples-bc: $(BC_EXAMPLES)

${BUILDDIR}/bc/%.txt: examples/snippets/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/bc
	${SLANGC} -o $@ --backend-bc $< runtime/std.slang

${BUILDDIR}/bc:
	mkdir -p ${BUILDDIR}/bc

# Example compiled to slang-code!
.PHONY: all-examples-slang
all-examples-slang: $(SLANG2_EXAMPLES) # TODO: $(SLANG3_EXAMPLES)

${BUILDDIR}/slang/%.slang: examples/snippets/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/slang
	${SLANGC} -o $@ --backend-slang $< runtime/std.slang

${BUILDDIR}/slang:
	mkdir -p ${BUILDDIR}/slang

# Validate slang code by compiling generated slang code again:
${BUILDDIR}/slang3/%.slang: ${BUILDDIR}/slang/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/slang3
	${SLANGC} -o $@ --backend-slang $< runtime/std.slang

${BUILDDIR}/slang3:
	mkdir -p ${BUILDDIR}/slang3

# Example compiled to Python code:
.PHONY: all-examples-python
all-examples-python: $(PY_EXAMPLES)

${BUILDDIR}/python/snippet-%.py: examples/snippets/%.slang runtime/std.slang ${BUILDDIR}/python/slangrt.py ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ $< runtime/std.slang

# examples compiled to C code:
.PHONY: all-examples-c
all-examples-c: $(C_EXAMPLES) $(C_EXAMPLES_2)

.PRECIOUS: ${BUILDDIR}/c/snippets/%.exe ${BUILDDIR}/c/snippets/%.c
${BUILDDIR}/c/snippets/%.exe: ${BUILDDIR}/c/snippets/%.c ${BUILDDIR}/slangrt.a runtime/slangrt.h | ${BUILDDIR}/c/snippets
	gcc ${CFLAGS} -o $@ $< ${BUILDDIR}/slangrt.a -lm

${BUILDDIR}/c/snippets/%.c: examples/snippets/%.slang runtime/std.slang ${SLANGC_DEPS} | ${BUILDDIR}/c/snippets
	${SLANGC} --backend-c-v2 -o $@ $< runtime/std.slang

${BUILDDIR}/c/snippets:
	mkdir -p ${BUILDDIR}/c/snippets

# Examples compiled to C code via bytecode:
.PRECIOUS: ${BUILDDIR}/c/snippets2/%.exe ${BUILDDIR}/c/snippets2/%.c
${BUILDDIR}/c/snippets2/%.exe: ${BUILDDIR}/c/snippets2/%.c ${BUILDDIR}/slangrt.a runtime/slangrt.h | ${BUILDDIR}/c/snippets2
	gcc ${CFLAGS} -o $@ $< ${BUILDDIR}/slangrt.a -lm

${BUILDDIR}/c/snippets2/%.c: examples/snippets/%.slang runtime/std.slang ${SLANGC_DEPS} | ${BUILDDIR}/c/snippets2
	${SLANGC} --backend-c -o $@ $< runtime/std.slang

${BUILDDIR}/c/snippets2:
	mkdir -p ${BUILDDIR}/c/snippets2

# Base lib as DLL:
${BUILDDIR}/c/libbase.c ${BUILDDIR}/c/libbase.json: ${BASE_LIB_SRCS} ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c-v2 --gen-export ${BUILDDIR}/c/libbase.json -o ${BUILDDIR}/c/libbase.c ${BASE_LIB_SRCS}

${BUILDDIR}/c/libimage.c ${BUILDDIR}/c/libimage.json: ${IMAGE_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c-v2 --gen-export ${BUILDDIR}/c/libimage.json -o ${BUILDDIR}/c/libimage.c --add-import ${BUILDDIR}/c/libbase.json ${IMAGE_LIB_SRCS}

${BUILDDIR}/c/libgfx.c ${BUILDDIR}/c/libgfx.json: ${GFX_LIB_SRCS} ${BUILDDIR}/c/libimage.json ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c-v2 --gen-export ${BUILDDIR}/c/libgfx.json -o ${BUILDDIR}/c/libgfx.c --add-import ${BUILDDIR}/c/libimage.json --add-import ${BUILDDIR}/c/libbase.json ${GFX_LIB_SRCS}

${BUILDDIR}/c/libweb.c ${BUILDDIR}/c/libweb.json: ${WEB_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c-v2 --gen-export ${BUILDDIR}/c/libweb.json -o ${BUILDDIR}/c/libweb.c --add-import ${BUILDDIR}/c/libbase.json ${WEB_LIB_SRCS}

${BUILDDIR}/c/libscience.c ${BUILDDIR}/c/libscience.json: ${SCIENCE_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c-v2 --gen-export ${BUILDDIR}/c/libscience.json -o ${BUILDDIR}/c/libscience.c --add-import ${BUILDDIR}/c/libbase.json ${SCIENCE_LIB_SRCS}

${BUILDDIR}/c/libcompiler.c ${BUILDDIR}/c/libcompiler.json: ${COMPILER_LIB_SRCS} ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/c
	${SLANGC} --backend-c-v2 --gen-export ${BUILDDIR}/c/libcompiler.json -o ${BUILDDIR}/c/libcompiler.c --add-import ${BUILDDIR}/c/libbase.json ${COMPILER_LIB_SRCS}

.PRECIOUS: ${BUILDDIR}/c/lib%.so
${BUILDDIR}/c/lib%.so: ${BUILDDIR}/c/lib%.c
	gcc ${CFLAGS} -shared -fPIC -o $@ $<

# Base lib as python module
${BUILDDIR}/python/libbase.py ${BUILDDIR}/python/libbase.json: ${BASE_LIB_SRCS} ${SLANGC_DEPS} | ${BUILDDIR}/python ${BUILDDIR}/python/slangrt.py
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libbase.json -o ${BUILDDIR}/python/libbase.py ${BASE_LIB_SRCS}

${BUILDDIR}/python/libimage.py ${BUILDDIR}/python/libimage.json: ${IMAGE_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python ${BUILDDIR}/python/slangrt.py
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libimage.json -o ${BUILDDIR}/python/libimage.py --add-import ${BUILDDIR}/python/libbase.json ${IMAGE_LIB_SRCS}

${BUILDDIR}/python/libgfx.py ${BUILDDIR}/python/libgfx.json: ${GFX_LIB_SRCS} ${BUILDDIR}/python/libimage.json ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python ${BUILDDIR}/python/slangrt.py
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libgfx.json -o ${BUILDDIR}/python/libgfx.py --add-import ${BUILDDIR}/python/libimage.json --add-import ${BUILDDIR}/python/libbase.json ${GFX_LIB_SRCS}

${BUILDDIR}/python/libweb.py ${BUILDDIR}/python/libweb.json: ${WEB_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python ${BUILDDIR}/python/slangrt.py
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libweb.json -o ${BUILDDIR}/python/libweb.py --add-import ${BUILDDIR}/python/libbase.json ${WEB_LIB_SRCS}

${BUILDDIR}/python/libscience.py ${BUILDDIR}/python/libscience.json: ${SCIENCE_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python ${BUILDDIR}/python/slangrt.py
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libscience.json -o ${BUILDDIR}/python/libscience.py --add-import ${BUILDDIR}/python/libbase.json ${SCIENCE_LIB_SRCS}

${BUILDDIR}/python/libcompiler.py ${BUILDDIR}/python/libcompiler.json: ${COMPILER_LIB_SRCS} ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python ${BUILDDIR}/python/slangrt.py
	${SLANGC} --backend-py --gen-export ${BUILDDIR}/python/libcompiler.json -o ${BUILDDIR}/python/libcompiler.py --add-import ${BUILDDIR}/python/libbase.json ${COMPILER_LIB_SRCS}

# linkage-example: ${BUILDDIR}/c/linkage-main.exe
${BUILDDIR}/c/linkage/libfubar.c ${BUILDDIR}/c/linkage/libfubar.json: examples/linkage/fubar.slang ${SLANGC_DEPS} | ${BUILDDIR}/c/linkage
	${SLANGC} --backend-c -v -v --gen-export ${BUILDDIR}/c/linkage/libfubar.json -o ${BUILDDIR}/c/linkage/libfubar.c examples/linkage/fubar.slang runtime/std.slang

${BUILDDIR}/c/linkage/libfancy.c ${BUILDDIR}/c/linkage/libfancy.json: examples/linkage/fancy.slang ${BUILDDIR}/c/linkage/libfubar.json ${SLANGC_DEPS} | ${BUILDDIR}/c/linkage
	${SLANGC} --backend-c -v -v --gen-export ${BUILDDIR}/c/linkage/libfancy.json -o ${BUILDDIR}/c/linkage/libfancy.c --add-import ${BUILDDIR}/c/linkage/libfubar.json examples/linkage/fancy.slang

${BUILDDIR}/c/linkage/main.c: examples/linkage/main.slang ${BUILDDIR}/c/linkage/libfancy.json ${SLANGC_DEPS} | ${BUILDDIR}/c/linkage
	jq '.' ${BUILDDIR}/c/linkage/libfancy.json --indent 5
	${SLANGC} --backend-c -v -v --add-import ${BUILDDIR}/c/linkage/libfancy.json --add-import ${BUILDDIR}/c/linkage/libfubar.json -o $@ examples/linkage/main.slang

${BUILDDIR}/c/linkage/libfancy.so: ${BUILDDIR}/c/linkage/libfancy.c
	gcc ${CFLAGS} -shared -fPIC -o $@ $<

${BUILDDIR}/c/linkage/main.exe: ${BUILDDIR}/c/linkage/main.c ${BUILDDIR}/c/linkage/libfancy.so ${BUILDDIR}/slangrt.a runtime/slangrt.h
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c/linkage -Wl,-rpath=`pwd`/${BUILDDIR}/c/linkage -l:libfancy.so ${BUILDDIR}/slangrt.a -lm

${BUILDDIR}/c/linkage:
	mkdir -p ${BUILDDIR}/c/linkage

linkage: ${BUILDDIR}/c/linkage/main.exe

# Native code
${BUILDDIR}/c/native_example/t1.o: examples/native/t1.slang ${SLANGC_DEPS} | ${BUILDDIR}/c/native_example
	${SLANGC} --backend-x86 -v -v -o $@ $<

${BUILDDIR}/c/native_example/main.exe: examples/native/main.c ${BUILDDIR}/c/native_example/t1.o | ${BUILDDIR}/c/native_example
	gcc -o $@ $< ${BUILDDIR}/c/native_example/t1.o

${BUILDDIR}/c/native_example:
	mkdir -p ${BUILDDIR}/c/native_example

# x86 backend
native_example: ${BUILDDIR}/c/native_example/main.exe

.PRECIOUS: ${BUILDDIR}/x86/snippet_%.o

${BUILDDIR}/x86/snippet_%.o: examples/snippets/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} --backend-x86 --debug -o $@ $< runtime/std.slang

${BUILDDIR}/x86/snippet_%.exe: ${BUILDDIR}/x86/snippet_%.o ${BUILDDIR}/slangrt.a | ${BUILDDIR}/x86
	gcc -o $@ $< ${BUILDDIR}/slangrt.a

${BUILDDIR}/x86:
	mkdir -p ${BUILDDIR}/x86

.PHONY: all-examples-x86
all-examples-x86: $(X86_EXAMPLES)

native: all-examples-x86 native_example

# Libs to x86
${BUILDDIR}/x86/libbase.o ${BUILDDIR}/x86/libbase.json: ${BASE_LIB_SRCS} ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} -v --backend-x86 --gen-export ${BUILDDIR}/x86/libbase.json -o ${BUILDDIR}/x86/libbase.o ${BASE_LIB_SRCS}

${BUILDDIR}/x86/libcompiler.o ${BUILDDIR}/x86/libcompiler.json: ${COMPILER_LIB_SRCS} ${BUILDDIR}/x86/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} -v --backend-x86 --gen-export ${BUILDDIR}/x86/libcompiler.json -o ${BUILDDIR}/x86/libcompiler.o --add-import ${BUILDDIR}/x86/libbase.json ${COMPILER_LIB_SRCS}

${BUILDDIR}/x86/libimage.o ${BUILDDIR}/x86/libimage.json: ${IMAGE_LIB_SRCS} ${BUILDDIR}/x86/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} -v --backend-x86 --gen-export ${BUILDDIR}/x86/libimage.json -o ${BUILDDIR}/x86/libimage.o --add-import ${BUILDDIR}/x86/libbase.json ${IMAGE_LIB_SRCS}

${BUILDDIR}/x86/libscience.o ${BUILDDIR}/x86/libscience.json: ${SCIENCE_LIB_SRCS} ${BUILDDIR}/x86/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} -v --backend-x86 --gen-export ${BUILDDIR}/x86/libscience.json -o ${BUILDDIR}/x86/libscience.o --add-import ${BUILDDIR}/x86/libbase.json ${SCIENCE_LIB_SRCS}

# Tests to x86
.PRECIOUS: ${BUILDDIR}/x86/test_%.o
${BUILDDIR}/x86/test_%.o: tests/test_%.slang ${BUILDDIR}/x86/libbase.json ${BUILDDIR}/x86/libcompiler.json ${BUILDDIR}/x86/libimage.json ${BUILDDIR}/x86/libscience.json ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} --backend-x86 -o $@ $< --add-import ${BUILDDIR}/x86/libbase.json --add-import ${BUILDDIR}/x86/libcompiler.json --add-import ${BUILDDIR}/x86/libimage.json --add-import ${BUILDDIR}/x86/libscience.json

.PRECIOUS: ${BUILDDIR}/x86/test_%.exe
${BUILDDIR}/x86/test_%.exe: ${BUILDDIR}/x86/test_%.o ${BUILDDIR}/x86/libbase.o ${BUILDDIR}/x86/libcompiler.o ${BUILDDIR}/x86/libimage.o ${BUILDDIR}/x86/libscience.o ${BUILDDIR}/slangrt.a
	gcc -o $@ $< ${BUILDDIR}/x86/libbase.o ${BUILDDIR}/x86/libcompiler.o ${BUILDDIR}/x86/libimage.o ${BUILDDIR}/x86/libscience.o ${BUILDDIR}/slangrt.a

# Compiler to x86
.PRECIOUS: ${BUILDDIR}/x86/compiler.o
${BUILDDIR}/x86/compiler.o: ${COMPILER_SRCS} ${BUILDDIR}/x86/libbase.json ${BUILDDIR}/x86/libcompiler.json ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} --backend-x86 -o $@ ${COMPILER_SRCS} --add-import ${BUILDDIR}/x86/libbase.json --add-import ${BUILDDIR}/x86/libcompiler.json

${BUILDDIR}/x86/compiler.exe: ${BUILDDIR}/x86/compiler.o ${BUILDDIR}/x86/libbase.o ${BUILDDIR}/x86/libcompiler.o ${BUILDDIR}/slangrt.a
	gcc -o $@ ${BUILDDIR}/x86/compiler.o ${BUILDDIR}/x86/libbase.o ${BUILDDIR}/x86/libcompiler.o ${BUILDDIR}/slangrt.a

${BUILDDIR}/x86/compiler8.o: ${COMPILER_SRCS} ${BASE_LIB_SRCS} ${COMPILER_LIB_SRCS} ${BUILDDIR}/x86/compiler.exe | ${BUILDDIR}
	./${BUILDDIR}/x86/compiler.exe -v --backend-x86 -o $@ ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${BUILDDIR}/x86/compiler8.exe: ${BUILDDIR}/x86/compiler8.o ${BUILDDIR}/slangrt.a
	gcc -o $@ ${BUILDDIR}/x86/compiler8.o ${BUILDDIR}/slangrt.a

${BUILDDIR}/x86/compiler9.o: ${COMPILER_SRCS} ${BASE_LIB_SRCS} ${COMPILER_LIB_SRCS} ${BUILDDIR}/x86/compiler8.exe | ${BUILDDIR}
	./${BUILDDIR}/x86/compiler8.exe -v --backend-x86 -o $@ ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}
	diff ${BUILDDIR}/x86/compiler9.o ${BUILDDIR}/x86/compiler8.o

${BUILDDIR}/x86/compiler9.exe: ${BUILDDIR}/x86/compiler9.o ${BUILDDIR}/slangrt.a
	gcc -o $@ ${BUILDDIR}/x86/compiler9.o ${BUILDDIR}/slangrt.a

# Advent-of-Code compiled to X86
.PRECIOUS: ${BUILDDIR}/x86/aoc_%.o
${BUILDDIR}/x86/aoc_%.o: examples/aoc/%/main.slang ${BUILDDIR}/x86/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/x86
	${SLANGC} --backend-x86 -o $@ $< --add-import ${BUILDDIR}/x86/libbase.json

${BUILDDIR}/x86/aoc_%.exe: ${BUILDDIR}/x86/aoc_%.o ${BUILDDIR}/x86/libbase.o ${BUILDDIR}/slangrt.a
	gcc -o $@ $< ${BUILDDIR}/x86/libbase.o ${BUILDDIR}/slangrt.a

.PHONY: all-tests-x86
all-tests-x86: ${X86_TESTS}

.PHONY: run-test-x86-%
run-test-x86-%: ${BUILDDIR}/x86/test_%.exe
	$<

# Risc-V
${BUILDDIR}/riscv:
	mkdir -p ${BUILDDIR}/riscv

${BUILDDIR}/riscv/t1.o: examples/native/t1.slang ${SLANGC_DEPS} | ${BUILDDIR}/riscv
	${SLANGC} --backend-riscv -v -v --report -o $@ $<

.PRECIOUS: ${BUILDDIR}/riscv/snippet_%.o
${BUILDDIR}/riscv/snippet_%.o: examples/snippets/%.slang ${SLANGC_DEPS} | ${BUILDDIR}/riscv
	${SLANGC} --backend-riscv -v -v --report --debug -o $@ $< runtime/std.slang

.PRECIOUS: ${BUILDDIR}/riscv/snippet_%.elf
${BUILDDIR}/riscv/snippet_%.elf: ${BUILDDIR}/riscv/snippet_%.o ${BUILDDIR}/riscv/crt.o examples/riscv/rv.ld | ${BUILDDIR}/riscv
	riscv32-elf-ld -T examples/riscv/rv.ld -o $@ $< ${BUILDDIR}/riscv/crt.o

${BUILDDIR}/riscv/crt.o: examples/riscv/crt.s | ${BUILDDIR}/riscv
	riscv32-elf-as -march=rv32im -o $@ $<

run-riscv-%: ${BUILDDIR}/riscv/snippet_%.elf
	qemu-system-riscv32 -machine virt -cpu rv32 -bios none -kernel $<

# Wasm examples:
.PHONY: all-examples-wasm
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

${BUILDDIR}/tests/test_%.c: tests/test_%.slang ${BUILDDIR}/c/libcompiler.json ${BUILDDIR}/c/libimage.json ${BUILDDIR}/c/libscience.json ${BUILDDIR}/c/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/tests
	${SLANGC} --backend-c-v2 -o $@ $< --add-import ${BUILDDIR}/c/libcompiler.json --add-import ${BUILDDIR}/c/libimage.json --add-import ${BUILDDIR}/c/libscience.json --add-import ${BUILDDIR}/c/libbase.json

${BUILDDIR}/tests/test_%.exe: ${BUILDDIR}/tests/test_%.c ${BUILDDIR}/c/libcompiler.so ${BUILDDIR}/c/libimage.so ${BUILDDIR}/c/libscience.so ${BUILDDIR}/c/libbase.so ${BUILDDIR}/slangrt.a
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c -Wl,-rpath=`pwd`/${BUILDDIR}/c -l:libcompiler.so -l:libimage.so -l:libscience.so -l:libbase.so ${BUILDDIR}/slangrt.a -lm

# Unit tests with python backend:
.PHONY: run-test-py-%
.PRECIOUS: ${BUILDDIR}/python/test_%.py
run-test-py-%: ${BUILDDIR}/python/test_%.py ${BUILDDIR}/python/slangrt.py
	python $<

${BUILDDIR}/python/slangrt.py: runtime/slangrt.py | ${BUILDDIR}/python
	cp $< $@

${BUILDDIR}/python/test_%.py: tests/test_%.slang ${BUILDDIR}/python/libcompiler.json ${BUILDDIR}/python/libimage.json ${BUILDDIR}/python/libscience.json ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ --add-import ${BUILDDIR}/python/libcompiler.json --add-import ${BUILDDIR}/python/libimage.json --add-import ${BUILDDIR}/python/libscience.json --add-import ${BUILDDIR}/python/libbase.json $<

# Apps
.PRECIOUS: ${BUILDDIR}/c/apps/%.c
${BUILDDIR}/c/apps/%.c: Apps/%.slang ${BUILDDIR}/c/libbase.json ${BUILDDIR}/c/libimage.json ${BUILDDIR}/c/libscience.json ${BUILDDIR}/c/libgfx.json ${BUILDDIR}/c/libcompiler.json ${BUILDDIR}/c/libweb.json ${SLANGC_DEPS} | ${BUILDDIR}/c/apps
	${SLANGC} --backend-c-v2 -o $@ $< --add-import ${BUILDDIR}/c/libbase.json --add-import ${BUILDDIR}/c/libimage.json --add-import ${BUILDDIR}/c/libscience.json --add-import ${BUILDDIR}/c/libgfx.json --add-import ${BUILDDIR}/c/libcompiler.json --add-import ${BUILDDIR}/c/libweb.json

${BUILDDIR}/c/apps/%.exe: ${BUILDDIR}/c/apps/%.c ${BUILDDIR}/c/libbase.so ${BUILDDIR}/c/libimage.so ${BUILDDIR}/c/libgfx.so ${BUILDDIR}/c/libscience.so ${BUILDDIR}/c/libcompiler.so ${BUILDDIR}/c/libweb.so ${BUILDDIR}/slangrt.a
	gcc ${CFLAGS} -o $@ $< -L${BUILDDIR}/c -Wl,-rpath=`pwd`/${BUILDDIR}/c -l:libweb.so -l:libcompiler.so -l:libgfx.so -l:libimage.so -l:libscience.so -l:libbase.so ${BUILDDIR}/slangrt.a -lm

# Apps compiled to python
${BUILDDIR}/python/app-%.py: Apps/%.slang ${BUILDDIR}/python/libbase.json ${BUILDDIR}/python/libimage.json ${BUILDDIR}/python/libscience.json ${BUILDDIR}/python/libgfx.json ${BUILDDIR}/python/libcompiler.json ${BUILDDIR}/python/libweb.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ $< --add-import ${BUILDDIR}/python/libbase.json --add-import ${BUILDDIR}/python/libimage.json --add-import ${BUILDDIR}/python/libscience.json --add-import ${BUILDDIR}/python/libgfx.json --add-import ${BUILDDIR}/python/libcompiler.json --add-import ${BUILDDIR}/python/libweb.json

# Advent-of-Code compiled to python
${BUILDDIR}/python/aoc-%.py: examples/aoc/%/main.slang ${BUILDDIR}/python/libbase.json ${SLANGC_DEPS} | ${BUILDDIR}/python
	${SLANGC} --backend-py -o $@ $< --add-import ${BUILDDIR}/python/libbase.json

# Bootstrap sequence:
${COMPILER1}: | ${BUILDDIR}
	python bootstrap.py

${BUILDDIR}/slangrt.py: runtime/slangrt.py | ${BUILDDIR}
	cp $< $@

${COMPILER2}: | ${BUILDDIR}/slangrt.py ${COMPILER1} ${BUILDDIR}
	python ${COMPILER1} --backend-py -o ${COMPILER2} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER3}: | ${BUILDDIR}/slangrt.py ${COMPILER2} ${BUILDDIR}
	python ${COMPILER2} --backend-py -o ${COMPILER3} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${BUILDDIR}/tmp-compiler4.c: | ${COMPILER3} ${BUILDDIR}
	python ${COMPILER3} --backend-c -o ${BUILDDIR}/tmp-compiler4.c ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER4}: ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/slangrt.a runtime/slangrt.h | ${BUILDDIR}
	gcc ${CFLAGS} -o ${COMPILER4} ${BUILDDIR}/tmp-compiler4.c ${BUILDDIR}/slangrt.a -lm

${BUILDDIR}/tmp-compiler5.c: ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${COMPILER4} | ${BUILDDIR} ${BASE_LIB_SRCS}
	./${COMPILER4} --backend-c -o ${BUILDDIR}/tmp-compiler5.c ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER5}: ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/slangrt.a runtime/slangrt.h | ${BUILDDIR}
	gcc ${CFLAGS} -o ${COMPILER5} ${BUILDDIR}/tmp-compiler5.c ${BUILDDIR}/slangrt.a -lm

${COMPILER6}: ${COMPILER_SRCS} ${BASE_LIB_SRCS} ${COMPILER_LIB_SRCS} ${COMPILER5} | ${BUILDDIR}
	./${COMPILER5} --backend-py -o ${COMPILER6} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${COMPILER7}: ${COMPILER_SRCS} ${BASE_LIB_SRCS} ${COMPILER_LIB_SRCS} ${BUILDDIR}/x86/compiler.exe | ${BUILDDIR}
	./${BUILDDIR}/x86/compiler.exe --backend-py -o ${COMPILER7} ${COMPILER_SRCS} ${COMPILER_LIB_SRCS} ${BASE_LIB_SRCS}

${BUILDDIR}/compiler.wat: ${COMPILER_SRCS} ${COMPILER6} | ${BUILDDIR}
	python ${COMPILER6} -wasm ${COMPILER_SRCS}

# Helper targets:
${BUILDDIR}:
	mkdir -p ${BUILDDIR}

${BUILDDIR}/c:
	mkdir -p ${BUILDDIR}/c

${BUILDDIR}/python:
	mkdir -p ${BUILDDIR}/python

${BUILDDIR}/wasm:
	mkdir -p ${BUILDDIR}/wasm

${BUILDDIR}/tests:
	mkdir -p ${BUILDDIR}/tests

${BUILDDIR}/c/apps:
	mkdir -p ${BUILDDIR}/c/apps

${BUILDDIR}/slangrt.a: ${BUILDDIR}/slangrt.o ${BUILDDIR}/slangrt_mm.o | ${BUILDDIR}
	ar cr $@ ${BUILDDIR}/slangrt.o ${BUILDDIR}/slangrt_mm.o

${BUILDDIR}/slangrt.o: runtime/slangrt.c runtime/slangrt.h | ${BUILDDIR}
	gcc ${CFLAGS} -c -o $@ $<

${BUILDDIR}/slangrt_mm.o: runtime/slangrt_mm.c runtime/slangrt.h | ${BUILDDIR}
	gcc ${CFLAGS} -c -o $@ $<


.PHONY: clean
clean:
	rm -rf ${BUILDDIR}

.SUFFIXES:
