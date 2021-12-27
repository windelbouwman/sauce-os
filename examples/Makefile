
export RUST_BACKTRACE=1
export PYTHONPATH=..
SLANG_COMPILER=../compiler2/target/debug/compiler2 -vvv
# SLANG_COMPILER=python -m bootstrap-compiler.main

EXECUTABLES = \
	callings.exe \
	expressions.exe \
	hello-world.exe \
	if-statements.exe \
	structs-passing.exe

.PHONY: all
all: ${EXECUTABLES}

runtime.o: ../runtime/runtime.c
	gcc -c -o runtime.o ../runtime/runtime.c

%.exe: %.o runtime.o Makefile
	gcc $< runtime.o -o $@

%.o: %.ll Makefile
	llc --relocation-model=pic -filetype=obj -o $@ $<

.PRECIOUS: %.ll
.SUFFIXES: .slang
%.ll: %.slang Makefile
	${SLANG_COMPILER} --output $@ $<

clean:
	rm -f *.ll *.o *.exe
