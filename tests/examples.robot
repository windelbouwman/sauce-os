
*** Settings ***
Library  Process
Library  OperatingSystem

*** Variables ***
${EXAMPLES_FOLDER}      ../examples
${SLANG_COMPILER}       ../compiler2/target/debug/compiler2

*** Test Cases ***
Hello world
    Compile and run hello-world example

Expressions
    Compile and run expressions example

If statements
    Compile and run if-statements example

Callings
    Compile and run callings example

Struct passing
    Compile and run structs-passing example


*** Keywords ***
Compile and run ${filename} example
    Compile slang code for ${filename}
    Invoke LLVM text ${filename}
    Create executable for ${filename}
    Run executable for ${filename}

Compile slang code for ${filename}
    ${result}=  Run Process  ${SLANG_COMPILER}  -vvv  ${EXAMPLES_FOLDER}/${filename}.slang  --output  ${EXAMPLES_FOLDER}/${filename}.ll
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

Invoke LLVM text ${filename}
    ${result}=  Run Process  llc  --relocation-model\=pic  -filetype\=obj  -o  ${EXAMPLES_FOLDER}/${filename}.o  ${EXAMPLES_FOLDER}/${filename}.ll
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

Create executable for ${filename}
    ${result}=  Run Process  gcc  -o  ${EXAMPLES_FOLDER}/${filename}.exe  ${EXAMPLES_FOLDER}/build/runtime.o  ${EXAMPLES_FOLDER}/${filename}.o
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0

Run executable for ${filename}
    ${result}=  Run Process  ${EXAMPLES_FOLDER}/${filename}.exe
    Log  ${result.stdout}
    Log  ${result.stderr}

    # TODO: check exit code:
    # Should Be Equal As Integers  ${result.rc}  0

    ${expected}=  Get File  ${EXAMPLES_FOLDER}/${filename}.stdout
    Should Be Equal  ${expected}  ${result.stdout}
