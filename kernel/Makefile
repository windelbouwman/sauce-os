
SLANG_COMPILER=../compiler2/target/debug/compiler2
BUILDDIR=build

all: ${BUILDDIR} ${BUILDDIR}/kernel.elf

${BUILDDIR}:
	mkdir -p ${BUILDDIR}

myos.iso: ${BUILDDIR}/kernel.elf grub.cfg
	mkdir -p isodir/boot/grub
	cp ${BUILDDIR}/kernel.elf isodir/boot/kernel.bin
	cp grub.cfg isodir/boot/grub/grub.cfg
	grub-mkrescue -o myos.iso isodir

${BUILDDIR}/kernel.elf: ${BUILDDIR}/boot.o ${BUILDDIR}/kernel.o ${BUILDDIR}/kernel2.o
	# Use LLD linker
	ld.lld ${BUILDDIR}/boot.o ${BUILDDIR}/kernel.o ${BUILDDIR}/kernel2.o -o ${BUILDDIR}/kernel.elf
	grub-file --is-x86-multiboot ${BUILDDIR}/kernel.elf

${BUILDDIR}/kernel.o: kernel.c
	gcc -m32 -ffreestanding -c -o ${BUILDDIR}/kernel.o kernel.c

${BUILDDIR}/boot.o: boot.asm
	# Use NASM assembler
	nasm -f elf32 -o ${BUILDDIR}/boot.o boot.asm

${BUILDDIR}/%.o: ${BUILDDIR}/%.ll
	llc --relocation-model=pic -filetype=obj -march=x86 -o $@ $<

.SUFFIXES: .slang
.PRECIOUS: ${BUILDDIR}/%.ll
${BUILDDIR}/%.ll: %.slang
	${SLANG_COMPILER} --output $@ $<


clean:
	rm -rf ${BUILDDIR}
