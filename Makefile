
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

# Compile slang compiler:
${COMPILER3}: tmp-compiler2.py ${COMPILER_SRCS}
	echo "#!/usr/bin/env python" > ${COMPILER3}
	python ${COMPILER2} compiler/*.slang >> ${COMPILER3}
	chmod +x ${COMPILER3}

