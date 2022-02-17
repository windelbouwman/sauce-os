
# export PYTHONPATH=..
BUILDDIR=build
SLANG_COMPILER=../compiler2/target/release/compiler2
# SLANG_COMPILER=../compiler2/target/debug/compiler2
# SLANG_COMPILER=python -m bootstrap-compiler.main

EXECUTABLES = \
	${BUILDDIR}/callings.exe \
	${BUILDDIR}/classy.exe \
	${BUILDDIR}/expressions.exe \
	${BUILDDIR}/generics.exe \
	${BUILDDIR}/hello-world.exe \
	${BUILDDIR}/if-statements.exe \
	${BUILDDIR}/mandel.exe \
	${BUILDDIR}/structs-passing.exe

RT_OBJ=${BUILDDIR}/runtime.o

.PHONY: all
all: ${BUILDDIR} ${EXECUTABLES}

#compiler:
#	cargo build

${BUILDDIR}:
	mkdir -p ${BUILDDIR}

${RT_OBJ}: ../runtime/runtime.c
	gcc -c -o ${RT_OBJ} ../runtime/runtime.c

${BUILDDIR}/%.exe: ${BUILDDIR}/%.o ${RT_OBJ}
	gcc $< ${RT_OBJ} -o $@

${BUILDDIR}/%.o: ${BUILDDIR}/%.ll
	llc --relocation-model=pic -filetype=obj -o $@ $<

.SUFFIXES: .slang
.PRECIOUS: ${BUILDDIR}/%.ll
${BUILDDIR}/%.ll: %.slang
	${SLANG_COMPILER} --output $@ $<

clean:
	rm -rf ${BUILDDIR}
