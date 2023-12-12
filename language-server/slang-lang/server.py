"""
Idea: start language server, to provide autocompletion and diagnostics in vs-code.

"""

import logging
import time
import argparse
import glob
import rich.text
from asyncio import Queue

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
async def did_open(ls: LanguageServer, params: types.DidOpenTextDocumentParams):
    await _validate(ls, params)


@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
async def did_change(ls: LanguageServer, params: types.DidChangeTextDocumentParams):
    await _validate(ls, params)


work_q = Queue()


async def _validate(ls: LanguageServer, params):
    """Validate source code by compiling it using the null backend.

    This is time consuming cpu bound work,
    so must be handled in a seperate thread.
    """

    # Debounce!
    logger.info("validate! Might debounce?")

    text_doc = ls.workspace.get_document(params.text_document.uri)
    filename = text_doc.uri.removeprefix("file://")
    code = text_doc.source
    await work_q.put((filename, code))
    # logger.info("Validation completed")


async def validator_task(ls: LanguageServer, q: Queue):
    logger.info("Entering work task")
    while True:
        item = await q.get()
        if q.empty():
            filename, code = item
            result = await ls.loop.run_in_executor(None, _cpu_validate, filename, code)

            if result:
                ex = result
                diagnostic_per_file = {}
                for filename, location, message in ex.errors:
                    message = str(rich.text.Text.from_markup(message))
                    diagnostic = types.Diagnostic(
                        range=make_lsp_range(location),
                        severity=types.DiagnosticSeverity.Error,
                        message=message,
                    )
                    uri = "file://" + filename
                    if uri in diagnostic_per_file:
                        diagnostic_per_file[uri].append(diagnostic)
                    else:
                        diagnostic_per_file[uri] = [diagnostic]

                for uri, diagnostics in diagnostic_per_file.items():
                    ls.publish_diagnostics(uri, diagnostics)
            else:
                uri = "file://" + filename
                ls.publish_diagnostics(uri, [])
        else:
            # Skipping, newer data available!
            logger.info("Skipping task!")
        q.task_done()


def _cpu_validate(filename, code):
    """Potential CPU intensive operation"""
    options = CompilationOptions(backend="null")

    # Determine the source files
    # Heuristics to detect a 'slang-project.txt'
    logger.info(f"Compiling {filename}")
    # time.sleep(2)  # Artificial delay
    filenames = [(filename, code)]
    project_filename = find_project(filename)
    if project_filename:
        project_files = get_project_sources(project_filename)
        project_files.remove(filename)  # Skip this file itself
        filenames.extend(project_files)

    try:
        modules = do_compile(filenames, None, options)
        db.fill_infos(modules)
    except CompilationError as ex:
        result = ex
    else:
        result = None
    logger.info(f"Compiling {filename} done!")
    return result


def get_project_sources(project_filename: str):
    filenames = []
    # Add all files in the project:
    project_root = os.path.dirname(os.path.abspath(project_filename))
    project_sources = glob.glob(f"{project_root}/**/*.slang", recursive=True)
    filenames.extend(project_sources)

    # Add files listed in project file:
    with open(project_filename, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#"):
                continue
            if not line:
                continue
            path = os.path.normpath(os.path.join(project_root, line))
            if os.path.isdir(path):
                filenames.extend(glob.glob(f"{path}/**/*.slang", recursive=True))
            elif os.path.exists(path):
                filenames.append(path)
            else:
                logger.error(f"Invalid path: {path}")
    return filenames


def find_project(filename: str):
    """Search for slang-project.txt in some parent folders."""
    parent_folder = os.path.dirname(os.path.abspath(filename))
    while os.path.isdir(parent_folder):
        project_filename = os.path.join(parent_folder, "slang-project.txt")
        if os.path.exists(project_filename):
            return project_filename
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

    # TODO: kill tasks gently:
    task = server.loop.create_task(validator_task(server, work_q))

    if args.tcp:
        logging.getLogger("pygls.protocol").setLevel(logging.WARNING)
        logging.getLogger("namebinding").setLevel(logging.INFO)
        logging.getLogger("parser").setLevel(logging.INFO)
        logging.getLogger("basepass").setLevel(logging.INFO)
        logformat = "%(asctime)s | %(levelname)8s | %(name)10.10s | %(message)s"
        logging.basicConfig(level=logging.DEBUG, format=logformat)
        server.start_tcp("127.0.0.1", args.port)
    else:
        server.start_io()


main()
