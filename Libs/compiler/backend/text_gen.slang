
# Helper class to emit text code

from std import print, file_writeln, file_open, file_close
from datatypes import Option, option_is_some, option_unwrap
from strlib import str_repeat

class TextGenerator:
    var m_indentation: int = 0
    var use_file: bool = false
    var outf: int = 0
    var m_one_tab: str = "    "

    fn begin(output_filename: Option[str]):
        if option_is_some(output_filename):
            outf = file_open(filename: option_unwrap(output_filename), mode: "w")
            use_file = true

    fn end():
        if use_file:
            file_close(handle: outf)

    fn indent():
        m_indentation += 1

    fn dedent():
        m_indentation -= 1

    fn emit(text?: str):
        let indent = str_repeat(text: m_one_tab, count: m_indentation)
        let line = indent + text
        if use_file:
            file_writeln(handle: outf, line)
        else:
            print(line)

