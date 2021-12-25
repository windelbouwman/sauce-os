
*** Settings ***
# Library  SlangCompilerLibrary
Library  Process


*** Test Cases ***
Hello world
    Compile hello-world.slang


Expressions
    Compile expressions.slang

If statements
    Compile if-statements.slang


Callings
    Compile callings.slang


*** Keywords ***
Compile ${filename}
    ${result}=  Run Process  ../compiler2/target/debug/compiler2   -vvv  ../examples/${filename}  --output  ../examples/${filename}.ll
    Log  ${result.stdout}
    Log  ${result.stderr}
    Should Be Equal As Integers  ${result.rc}  0
