
export RUST_BACKTRACE=1
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
%.ll: %.slang ../bootstrap-compiler/*.py Makefile
	# python -m bootstrap-compiler.main $< --output $@
	../compiler2/target/debug/compiler2 -v -v $< --output $@

clean:
	rm -f *.ll *.o *.exe
