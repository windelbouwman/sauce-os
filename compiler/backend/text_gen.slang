
# Helper class to emit text code

from std import print, file_writeln, file_open, file_close
from datatypes import Option, option_is_some, option_unwrap
from strlib import str_repeat

class TextGenerator:
    var indentation: int = 0
    var use_file: bool = false
    var outf: int = 0

    fn begin(output_filename: Option[str]):
        if option_is_some(output_filename):
            outf = file_open(option_unwrap(output_filename))
            use_file = true

    fn end():
        if use_file:
            file_close(outf)

    fn indent():
        indentation += 1

    fn dedent():
        indentation -= 1

    fn emit(text?: str):
        let indent = str_repeat(text: "   ", count: indentation)
        let line = indent + text
        if use_file:
            file_writeln(outf, line)
        else:
            print(line)

