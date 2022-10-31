
*** Settings ***
Library  Process
Library  OperatingSystem

*** Variables ***
${EXAMPLES_FOLDER}      ../examples
${SLANG_COMPILER}       ../compiler2/target/debug/compiler2

*** Test Cases ***
Hello world compiled
    Compile and run hello-world example

Hello world interpreted
    Run hello-world example in interpreter

Expressions compiled
    Compile and run expressions example

Expressions interpreted
    Run expressions example in interpreter

If statements compiled
    Compile and run if-statements example

If statements interpreted
    Run if-statements example in interpreter

Callings compiled
    Compile and run callings example

Callings interpreted
    Run callings example in interpreter

Struct passing compiled
    Compile and run structs-passing example

Struct passing interpreted
    Run structs-passing example in interpreter

For loop compiled
    Compile and run for-loop example

For loop interpreted
    Run for-loop example in interpreter

Switching compiled
    Run switching example in interpreter

Switching interpreted
    Run switching example in interpreter

*** Keywords ***
Compile and run ${filename} example
    Compile slang code for ${filename}
    Invoke LLVM text ${filename}
    Create executable for ${filename}
    Run executable for ${filename}

Compile slang code for ${filename}
    ${result}=  Run Process  ${SLANG_COMPILER}  -vvv  ${EXAMPLES_FOLDER}/${filename}.slang  --output  ${EXAMPLES_FOLDER}/build/${filename}.ll
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

Invoke LLVM text ${filename}
    ${result}=  Run Process  llc  --relocation-model\=pic  -filetype\=obj  -o  ${EXAMPLES_FOLDER}/build/${filename}.o  ${EXAMPLES_FOLDER}/build/${filename}.ll
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

Create executable for ${filename}
    ${result}=  Run Process  gcc  -o  ${EXAMPLES_FOLDER}/build/${filename}.exe  ${EXAMPLES_FOLDER}/build/runtime.o  ${EXAMPLES_FOLDER}/build/${filename}.o
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

Run executable for ${filename}
    ${result}=  Run Process  ${EXAMPLES_FOLDER}/build/${filename}.exe
    Log  ${result.stdout}
    Log  ${result.stderr}

    # TODO: check exit code:
    # Should Be Equal As Integers  ${result.rc}  0

    ${expected}=  Get File  ${EXAMPLES_FOLDER}/${filename}.stdout
    Should Be Equal  ${expected}  ${result.stdout}

Run ${filename} example in interpreter
    ${result}=  Run Process  ${SLANG_COMPILER}  --execute-bytecode  ${EXAMPLES_FOLDER}/${filename}.slang
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

    ${expected}=  Get File  ${EXAMPLES_FOLDER}/${filename}.stdout
    Should Be Equal  ${expected}  ${result.stdout}
