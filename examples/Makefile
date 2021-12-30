
# export PYTHONPATH=..
BUILDDIR=build
SLANG_COMPILER=../compiler2/target/debug/compiler2
# SLANG_COMPILER=python -m bootstrap-compiler.main

EXECUTABLES = \
	callings.exe \
	expressions.exe \
	hello-world.exe \
	if-statements.exe \
	mandel.exe \
	structs-passing.exe

RT_OBJ=${BUILDDIR}/runtime.o

.PHONY: all
all: ${BUILDDIR} ${EXECUTABLES}

${BUILDDIR}:
	mkdir -p ${BUILDDIR}

${RT_OBJ}: ../runtime/runtime.c
	gcc -c -o ${RT_OBJ} ../runtime/runtime.c

%.exe: ${BUILDDIR}/%.o ${RT_OBJ}
	gcc $< ${RT_OBJ} -o $@

${BUILDDIR}/%.o: ${BUILDDIR}/%.ll
	llc --relocation-model=pic -filetype=obj -o $@ $<

.SUFFIXES: .slang
.PRECIOUS: ${BUILDDIR}/%.ll
${BUILDDIR}/%.ll: %.slang
	${SLANG_COMPILER} --output $@ $<

clean:
	rm -rf ${BUILDDIR} *.exe
