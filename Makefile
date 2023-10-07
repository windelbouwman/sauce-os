
COMPILER_SRCS=compiler/*.slang
COMPILER2=tmp-compiler2.py
COMPILER3=tmp-compiler3.py

all: hello-world loops structs-passing

# Compile hello world example:
hello-world: ${COMPILER3} examples/hello-world.slang
	python ${COMPILER3} -cv2 examples/hello-world.slang

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

compiler4: tmp-compiler4.c runtime/runtime.c
	gcc -Wno-incompatible-pointer-types -Wno-int-conversion -o compiler4 tmp-compiler4.c runtime/runtime.c

tmp-compiler4.c: ${COMPILER_SRCS} ${COMPILER3}
	python ${COMPILER3} -cv2 ${COMPILER_SRCS} | sed '/^# /d' > tmp-compiler4.c

tmp-compiler5.c: compiler4 ${COMPILER_SRCS}
	./compiler4 -cv2 ${COMPILER_SRCS} | sed '/^# /d' > tmp-compiler5.c

compiler5: tmp-compiler5.c runtime/runtime.c Makefile
	gcc -Wno-incompatible-pointer-types -Wno-int-conversion -o compiler5 tmp-compiler5.c runtime/runtime.c

generics2: ${COMPILER3} runtime/runtime.c examples/generics2.slang
	python ${COMPILER3} -cv2 examples/generics2.slang | sed '/^# /d' > generics2.c
	gcc generics2.c runtime/runtime.c

# Compile slang compiler:
${COMPILER3}: tmp-compiler2.py ${COMPILER_SRCS}
	echo "#!/usr/bin/env python" > ${COMPILER3}
	python ${COMPILER2} compiler/*.slang >> ${COMPILER3}
	chmod +x ${COMPILER3}

