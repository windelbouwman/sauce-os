
COMPILER_SRCS=compiler/*.slang
COMPILER2=tmp-compiler2.py
COMPILER3=tmp-compiler3.py

all: hello-world loops structs-passing

# Compile hello world example:
hello-world: ${COMPILER3} examples/hello-world.slang
	python ${COMPILER3} -bc examples/hello-world.slang

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
	python ${COMPILER3} -bc examples/generic-enum.slang

compiler4: ${COMPILER_SRCS} ${COMPILER3}
	python ${COMPILER3} -bc ${COMPILER_SRCS}

# Compile slang compiler:
${COMPILER3}: tmp-compiler2.py ${COMPILER_SRCS}
	echo "#!/usr/bin/env python" > ${COMPILER3}
	python ${COMPILER2} compiler/*.slang >> ${COMPILER3}
	chmod +x ${COMPILER3}

