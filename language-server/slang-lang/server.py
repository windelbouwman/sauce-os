"""
Idea: start language server, to provide autocompletion and diagnostics in vs-code.

"""

import logging
import time
import argparse
import glob

from pygls.server import LanguageServer
from lsprotocol import types

import sys, os

# TODO: this relative import is a bit lame..
sys.path.append(os.path.join(os.path.dirname(__file__), "..", ".."))
from compiler1.compiler import do_compile, CompilationOptions
from compiler1.errors import CompilationError
from compiler1.location import Location as SlangLocation, Position as SlangPosition
from compiler1 import ast

logger = logging.getLogger("Slang-Lang-LSP")

server = LanguageServer("Slang-Lang-Server", "v0.1")


class DataBase:
    """
    Symbol database.
    """

    def __init__(self):
        # Two layer deep reference map:
        self._references = {}  # Key is filename, then row

        # Key is ID, value is filename / location
        self._definitions = {}

        # Map from filename to module:
        self._file_modules = {}

    def fill_infos(self, modules):
        """Fill symbol info after compilation."""
        for module in modules:
            filename = module.filename
            if not os.path.exists(filename):
                continue

            for d_id, d_loc in module._definitions:
                self._definitions[str(d_id)] = (filename, d_loc)

            for r_id, r_loc in module._references:
                key = (filename, r_loc.begin.row)
                if key not in self._references:
                    self._references[key] = []
                self._references[key].append((r_loc, r_id))

            self._file_modules[filename] = module

    def get_definition(self, filename: str, position: SlangPosition):
        """Given a cursor, try to jump to definition."""
        key = (filename, position.row)
        if key in self._references:
            spots = self._references[key]
            for loc, def_id in spots:
                if loc.begin.column <= position.column <= loc.end.column:
                    key = str(def_id)
                    if key in db._definitions:
                        filename, loc = db._definitions[key]
                        return filename, loc
                    break


db = DataBase()


@server.feature(types.TEXT_DOCUMENT_COMPLETION)
def completions(params: types.CompletionParams) -> types.CompletionList:
    # items = []
    # document = server.workspace.get_document(params.text_document.uri)
    # current_line = document.lines[params.position.line].strip()
    # if current_line.endswith("hello."):
    items = [
        types.CompletionItem(label="world"),
        types.CompletionItem(label="hello"),
        types.CompletionItem(label="TODO"),
    ]
    return types.CompletionList(is_incomplete=False, items=items)


@server.feature(types.TEXT_DOCUMENT_INLAY_HINT)
def inlay_hints(params: types.InlayHintParams):
    print("GET INLAY HINTS", params)
    items = []
    for row in range(params.range.start.line, params.range.end.line):
        items.append(
            types.InlayHint(
                label="W))T",
                kind=types.InlayHintKind.Type,
                padding_left=False,
                padding_right=True,
                position=types.Position(line=row, character=0),
            )
        )
    return items


@server.feature(types.TEXT_DOCUMENT_DOCUMENT_SYMBOL)
def document_symbols(params: types.DocumentSymbolParams):
    document_uri = params.text_document.uri
    filename = document_uri.removeprefix("file://")
    symbols = []
    if filename in db._file_modules:
        module = db._file_modules[filename]
        for definition in module.definitions:
            symbols.append(definition_to_symbol(definition))
    return symbols


def definition_to_symbol(definition: ast.Definition):
    children = None
    kind = types.SymbolKind.Null
    if isinstance(definition, ast.ClassDef):
        kind = types.SymbolKind.Class
        children = []
        for subdef in definition.members:
            children.append(definition_to_symbol(subdef))
    elif isinstance(definition, ast.StructDef):
        kind = types.SymbolKind.Struct
        children = []
        for field in definition.fields:
            children.append(definition_to_symbol(field))
    elif isinstance(definition, ast.StructFieldDef):
        kind = types.SymbolKind.Field
    elif isinstance(definition, ast.FunctionDef):
        kind = types.SymbolKind.Function
    elif isinstance(definition, ast.EnumDef):
        kind = types.SymbolKind.Enum
        children = []
        for field in definition.variants:
            children.append(definition_to_symbol(field))
    elif isinstance(definition, ast.EnumVariant):
        kind = types.SymbolKind.EnumMember
    elif isinstance(definition, ast.VarDef):
        kind = types.SymbolKind.Variable

    range = make_lsp_range(definition.location)
    return types.DocumentSymbol(
        name=definition.id.name,
        kind=kind,
        range=range,
        selection_range=range,
        children=children,
    )


@server.feature(types.TEXT_DOCUMENT_DEFINITION)
def definition(ls: LanguageServer, params: types.DefinitionParams):
    text_doc = ls.workspace.get_document(params.text_document.uri)
    filename = text_doc.uri.removeprefix("file://")
    row = params.position.line + 1
    column = params.position.character + 1
    pos = db.get_definition(filename, SlangPosition(row, column))
    if pos:
        filename, loc = pos
        loc2 = types.Location(uri=f"file://{filename}", range=make_lsp_range(loc))
        return loc2


@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
def did_open(ls: LanguageServer, params: types.DidOpenTextDocumentParams):
    _validate(ls, params)


@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
def did_change(ls, params: types.DidChangeTextDocumentParams):
    _validate(ls, params)


def _validate(ls: LanguageServer, params):
    text_doc = ls.workspace.get_document(params.text_document.uri)

    options = CompilationOptions(backend="null")

    # Heuristics to detect a 'project'
    # TODO: figure out how to deal with a folder of files.
    filename = text_doc.uri.removeprefix("file://")
    code = text_doc.source
    std_filename = os.path.abspath("runtime/std.slang")
    project_root = find_project(filename)
    filenames = [(filename, code)]
    if project_root:
        filenames.extend(glob.glob(f"{project_root}/**/*.slang", recursive=True))
        filenames.remove(filename)
    filenames.append(std_filename)

    try:
        modules = do_compile(filenames, None, options)
        db.fill_infos(modules)
    except CompilationError as ex:
        for filename, location, message in ex.errors:
            diagnostics = []
            diagnostic = types.Diagnostic(
                range=make_lsp_range(location),
                severity=types.DiagnosticSeverity.Error,
                message=message,
            )
            diagnostics.append(diagnostic)
            uri = "file://" + filename
            ls.publish_diagnostics(uri, diagnostics)
    else:
        ls.publish_diagnostics(text_doc.uri, [])


def find_project(filename: str):
    """Search for slang-project.txt in some parent folders."""
    parent_folder = os.path.dirname(os.path.abspath(filename))
    while os.path.isdir(parent_folder):
        if os.path.exists(os.path.join(parent_folder, "slang-project.txt")):
            return parent_folder
        new_parent_folder = os.path.dirname(parent_folder)
        if new_parent_folder == parent_folder:
            break
        else:
            parent_folder = new_parent_folder


def make_lsp_range(location: SlangLocation) -> types.Range:
    return types.Range(
        make_lsp_position(location.begin), end=make_lsp_position(location.end)
    )


def make_lsp_position(location: SlangPosition) -> types.Position:
    return types.Position(location.row - 1, location.column - 1)


def main():
    parser = argparse.ArgumentParser(
        description="Start LSP server for Slang-Lang. Default start on stdio."
    )
    parser.add_argument("--port", type=int, default=8339)
    parser.add_argument("--tcp", help="Start a TCP server", action="store_true")
    args = parser.parse_args()

    if args.tcp:
        logging.getLogger("pygls.protocol").setLevel(logging.WARNING)
        logging.basicConfig(level=logging.DEBUG)
        server.start_tcp("127.0.0.1", args.port)
    else:
        server.start_io()


main()
