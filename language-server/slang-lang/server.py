"""
Slang lang language server.

Provide features:
- autocompletion
- diagnostics

Support VS-code and helix editors.

"""

import logging
import argparse
import glob
import time
import re
import asyncio
import sys
import os
import rich.text
from pygls.server import LanguageServer
from pygls.uris import to_fs_path, from_fs_path
from lsprotocol import types

# TODO: this relative import is a bit lame..
sys.path.append(os.path.join(os.path.dirname(__file__), "..", ".."))
from compiler1.compiler import do_compile, CompilationOptions
from compiler1.errors import CompilationError
from compiler1.location import Location as SlangLocation, Position as SlangPosition
from compiler1 import ast

logger = logging.getLogger("slls")  # Slang-lang language server (slls)


class DataBase:
    """Symbol database."""

    def __init__(self):
        # Key is ID, value is filename / location
        self._definitions = {}

        # Map from filename to file info
        self._file_infos = {}

        self._validation_task = None
        self.last_compilation_duration = 0

    def fill_infos(self, modules):
        """Fill symbol info after compilation."""
        for module in modules:
            filename = module.filename
            # if not os.path.exists(filename):
            #     logger.error(f"File not found: {filename}")
            #     continue

            for d_id, d_loc in module._definitions:
                self._definitions[str(d_id)] = (filename, d_loc)

            self._file_infos[filename] = FileInfo(module)

    def lookup(self, filename: str, position: SlangPosition, name: str):
        """Try to lookup a name at the given position."""
        if filename in self._file_infos:
            info = self._file_infos[filename]
            return info.lookup(position, name)

    async def validate(self, ls: LanguageServer, params, delay=0):
        """Validate source code by compiling it using the 'null' backend.

        This is time consuming cpu bound work,
        so must be handled in a seperate thread.
        """

        # Debounce!
        logger.info("validate! Might debounce?")
        await self.stop_validation()

        document = ls.workspace.get_text_document(params.text_document.uri)
        filename = to_fs_path(document.uri)
        code = document.source

        # Spawn a long running validation task:
        self._validation_task = asyncio.create_task(
            validator_task(ls, filename, code, delay)
        )

    async def stop_validation(self):
        if self._validation_task and not self._validation_task.done():
            logger.info("Cancelling validation task")
            self._validation_task.cancel()
            try:
                await self._validation_task
            except asyncio.CancelledError:
                logger.info("task cancelled")


async def validator_task(ls: LanguageServer, filename, code, delay):
    if delay:
        logger.info(f"Waiting {delay} seconds for additional changes")
        await asyncio.sleep(delay)
    logger.info("Start compilation!")
    filenames, ex = await ls.loop.run_in_executor(None, _cpu_validate, filename, code)

    diagnostics_per_file = {}
    # Create empty diagnostic lists per file:
    for filename in filenames:
        if isinstance(filename, tuple):
            filename = filename[0]
        uri = from_fs_path(filename)
        if uri not in diagnostics_per_file:
            diagnostics_per_file[uri] = []

    if ex:
        logger.debug("Compilation errors occurred")
        for filename, location, message in ex.errors:
            logger.debug(f"Error: {location} {message}")
            message = str(rich.text.Text.from_markup(message))
            diagnostic = types.Diagnostic(
                range=make_lsp_range(location),
                severity=types.DiagnosticSeverity.Error,
                message=message,
            )
            uri = from_fs_path(filename)
            if uri in diagnostics_per_file:
                diagnostics_per_file[uri].append(diagnostic)
            else:
                diagnostics_per_file[uri] = [diagnostic]

    for uri, diagnostics in diagnostics_per_file.items():
        ls.publish_diagnostics(uri, diagnostics)


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

    t1 = time.monotonic()
    try:
        modules = do_compile(filenames, None, options)
        db.fill_infos(modules)
    except CompilationError as ex:
        result = ex
    else:
        result = None
    t2 = time.monotonic()
    db.last_compilation_duration = t2 - t1
    logger.info(f"Compiling {filename} done in {db.last_compilation_duration} seconds!")
    return filenames, result


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


class FileInfo:
    """Information about a single text document / file."""

    def __init__(self, module: ast.Module):
        self.module = module
        self.scope_tree = module_to_scope_tree(module)

    def get_definitions_at(self, position: SlangPosition):
        return self.scope_tree.get_definitions_for_line(position.row)

    def lookup(self, position: SlangPosition, name: str):
        """Try to lookup a name at the given position"""
        return self.scope_tree.lookup(position.row, name)


class ScopeCrawler(ast.AstVisitor):
    """Walk entire AST, and build a tree of scopes"""

    def __init__(self):
        super().__init__()
        self.scope_stack = []

    def visit_module(self, module):
        logger.debug(f"Filling scopes for {module.name}")
        self.enter_scope(module.scope)
        super().visit_module(module)
        return self.leave_scope()

    def visit_definition(self, definition):
        if isinstance(definition, ast.ScopedDefinition):
            self.enter_scope(definition.scope)
        super().visit_definition(definition)
        if isinstance(definition, ast.ScopedDefinition):
            self.leave_scope()

    def visit_block(self, block):
        self.enter_scope(block.scope)
        super().visit_block(block)
        self.leave_scope()

    def enter_scope(self, scope):
        # logger.debug(f"Enter scope {scope.span}")
        item = ScopeTreeItem(scope)
        if self.scope_stack:
            self.scope_stack[-1].add_sub_scope(item)
        self.scope_stack.append(item)

    def leave_scope(self):
        # logger.debug("Leave scope")
        return self.scope_stack.pop()


class ScopeTreeItem:
    """A single scope level."""

    def __init__(self, scope: ast.Scope):
        assert isinstance(scope, ast.Scope)
        self.scope = scope
        self._m = RangeMap()

    def add_sub_scope(self, s: "ScopeTreeItem"):
        self._m.insert(s.scope.span.begin.row, s.scope.span.end.row, s)

    def lookup(self, row: int, name: str):
        # Try subscopes first:
        sub_item = self._m.get(row)
        if sub_item:
            obj = sub_item.lookup(row, name)
            if obj:
                return obj
        # Try own scope:
        if self.scope.is_defined(name):
            return self.scope.lookup(name)

    def get_definitions_for_line(self, row):
        definitions = []
        for symbol in list(self.scope.symbols.values()):
            if isinstance(symbol, ast.Definition):
                definitions.append(symbol)
        sub_item = self._m.get(row)
        if sub_item:
            definitions.extend(sub_item.get_definitions_for_line(row))
        return definitions


class RangeMap:
    """A mapping from a range to single objects."""

    def __init__(self):
        self._ranges = []

    def insert(self, key_begin, key_end, value):
        self._ranges.append((key_begin, key_end, value))

    def get(self, key):
        # TODO: replace linear scan with
        # a sorted heap
        for begin, end, value in self._ranges:
            if begin <= key < end:
                return value


def module_to_scope_tree(module: ast.Module) -> "ScopeTreeItem":
    """Create a tree of scopes"""
    logger.debug(f"Create scope tree for {module.name}")
    crawler = ScopeCrawler()
    return crawler.visit_module(module)


db = DataBase()
loop = asyncio.new_event_loop()
asyncio.set_event_loop(loop)
server = LanguageServer("Slang-Lang-Server", "v0.1", loop=loop)


@server.feature(
    types.TEXT_DOCUMENT_COMPLETION,
    types.CompletionOptions(trigger_characters=["."]),
)
async def completions(
    ls: LanguageServer, params: types.CompletionParams
) -> types.CompletionList:
    document = ls.workspace.get_text_document(params.text_document.uri)
    filename = to_fs_path(document.uri)
    position = make_slang_position(params.position)

    logger.debug(f"Gettin' completion {filename} / row {position} {params=}")
    items = []

    if (
        params.context is None
        or params.context.trigger_kind == types.CompletionTriggerKind.Invoked
    ):
        # CTRL+SPACE was pressed, fetch a full list of symbols.
        if filename in db._file_infos:
            info = db._file_infos[filename]
            items.extend(
                definitions_to_completion_items(info.get_definitions_at(position))
            )
    elif (
        params.context is not None
        and params.context.trigger_kind == types.CompletionTriggerKind.TriggerCharacter
        and params.context.trigger_character == "."
    ):
        # '.' was typed, try to get a list of members of the name before the '.'
        logger.debug("DOT INDEX")
        obj = get_def_under_cursor(document, lefted(params.position, 1))
        if obj:
            if isinstance(obj, (ast.Variable, ast.Parameter)):
                items.extend(
                    definitions_to_completion_items(obj.ty.get_inner_definitions())
                )
            elif isinstance(obj, ast.Module):
                items.extend(definitions_to_completion_items(obj.definitions))
            else:
                logger.debug(f"Cannot dot index {obj}")

    return types.CompletionList(is_incomplete=False, items=items)


def get_def_under_cursor(document, position):
    """Try to get to the definition under the position in the document"""
    # re_start_word = re.compile(r"[A-Za-z_0-9]*(\.[A-Za-z_0-9]+)*$")
    re_start_word = re.compile(r"[A-Za-z_0-9\.]*$")
    qual_name = document.word_at_position(position, re_start_word=re_start_word)
    if qual_name:
        filename = to_fs_path(document.uri)
        names = qual_name.split(".")
        name = names[0]
        logger.debug(f"Lookup: {name=}")
        obj = db.lookup(filename, make_slang_position(position), name)
        if obj:
            for attr in names[1:]:
                logger.debug(f"get attr {attr=}")
                if isinstance(obj, (ast.Variable, ast.Parameter)):
                    obj = obj.ty.get_inner_definition(attr)
                elif isinstance(obj, (ast.Module, ast.ScopedDefinition)):
                    if obj.scope.is_defined(attr):
                        obj = obj.scope.lookup(attr)
                    else:
                        return
                else:
                    logger.error(f"No impl get-attr {attr} from {obj=}")
                    return
            return obj
        else:
            logger.debug(f"Could not resolve {name}")
    else:
        logger.debug(f"No name: {qual_name}")


def definitions_to_completion_items(definitions: list[ast.Definition]):
    return [
        types.CompletionItem(
            label=definition.id.name, kind=get_completion_item_type(definition)
        )
        for definition in definitions
    ]


def get_completion_item_type(definition: ast.Definition):
    if isinstance(definition, ast.FunctionDef):
        kind = types.CompletionItemKind.Function
    elif isinstance(definition, ast.EnumDef):
        kind = types.CompletionItemKind.Enum
    elif isinstance(definition, ast.StructDef):
        kind = types.CompletionItemKind.Struct
    elif isinstance(definition, ast.ClassDef):
        kind = types.CompletionItemKind.Class
    elif isinstance(definition, ast.VarDef):
        kind = types.CompletionItemKind.Variable
    else:
        kind = types.CompletionItemKind.Variable
    return kind


# @server.feature(types.TEXT_DOCUMENT_INLAY_HINT)
# def inlay_hints(params: types.InlayHintParams):
#     logger.debug(f"GET INLAY HINTS: {params=}")
#     items = []
# for row in range(params.range.start.line, params.range.end.line):
# TODO: Insert inferred types into document
# items.append(
#     types.InlayHint(
#         label="W))T",
#         kind=types.InlayHintKind.Type,
#         padding_left=False,
#         padding_right=True,
#         position=types.Position(line=1, character=2),
#     )
# )
# return items


def lefted(p: types.Position, amount: int) -> types.Position:
    if p.character > amount:
        return types.Position(p.line, p.character - amount)
    else:
        return p


@server.feature(
    "textDocument/signatureHelp",
    types.SignatureHelpOptions(trigger_characters=["(", ","]),
)
def signature_help(ls: LanguageServer, params: types.SignatureHelpParams):
    logger.info(f"signature_help: {params=}")
    if (
        params.context is not None
        and params.context.trigger_kind
        == types.SignatureHelpTriggerKind.TriggerCharacter
        and params.context.trigger_character == "("
    ):
        document = ls.workspace.get_text_document(params.text_document.uri)
        obj = get_def_under_cursor(document, lefted(params.position, 1))
        if obj:
            logger.debug(f"Resolved {obj=}")
            if isinstance(obj, ast.FunctionDef):
                return types.SignatureHelp(
                    [function_def_to_signature(obj)],
                    active_signature=0,
                    active_parameter=0,
                )


def function_def_to_signature(
    function_def: ast.FunctionDef,
) -> types.SignatureInformation:
    parameters = []
    arg_texts = []
    for p in function_def.parameters:
        parameters.append(
            types.ParameterInformation(label=p.id.name, documentation="cool beans!")
        )
        arg_texts.append(f"{p.id.name}: {p.ty}")
    args = ", ".join(arg_texts)
    full_signature = f"{function_def.id.name}({args}) -> {function_def.return_ty}"
    return types.SignatureInformation(
        label=full_signature,
        documentation=function_def.docstring,
        parameters=parameters,
    )


@server.feature(
    "textDocument/hover",
)
def hover(ls: LanguageServer, params: types.HoverParams) -> types.Hover:
    document = ls.workspace.get_text_document(params.text_document.uri)
    # Check what object we hover over and give some nicely formatted information
    obj = get_def_under_cursor(document, params.position)
    if obj:
        logger.debug(f"Resolved {obj=}")
        if isinstance(obj, ast.FunctionDef):
            sig = function_def_to_signature(obj)
            return types.Hover(contents=[sig.label, sig.documentation])
        elif isinstance(obj, ast.StructDef):
            contents = types.MarkupContent(
                kind=types.MarkupKind.Markdown,
                value=f"# struct {obj.id.name}\n {obj.docstring}",
            )
            return types.Hover(contents=contents)
            # ,range=make_lsp_range()


@server.feature(types.TEXT_DOCUMENT_DOCUMENT_SYMBOL)
def document_symbols(params: types.DocumentSymbolParams):
    document_uri = params.text_document.uri
    filename = to_fs_path(document_uri)
    symbols = []
    if filename in db._file_infos:
        info = db._file_infos[filename]
        for definition in info.module.definitions:
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
    """Implement go to definition"""
    document = ls.workspace.get_text_document(params.text_document.uri)

    obj = get_def_under_cursor(document, params.position)
    if obj:
        pos = db._definitions.get(str(obj.id))
        if pos:
            filename, loc = pos
            return types.Location(uri=from_fs_path(filename), range=make_lsp_range(loc))


@server.feature(types.TEXT_DOCUMENT_DID_OPEN)
async def did_open(ls: LanguageServer, params: types.DidOpenTextDocumentParams):
    logger.debug("Doc open")
    await db.validate(ls, params, delay=0)


@server.feature(types.TEXT_DOCUMENT_DID_CHANGE)
async def did_change(ls: LanguageServer, params: types.DidChangeTextDocumentParams):
    logger.debug("Doc change")
    # Wait at least a factor between compilation attempts
    delay = max(db.last_compilation_duration * 7, 15)
    await db.validate(ls, params, delay=delay)


@server.feature(types.TEXT_DOCUMENT_DID_CLOSE)
async def did_close(ls: LanguageServer, params: types.DidOpenTextDocumentParams):
    uri = params.text_document.uri
    ls.publish_diagnostics(uri, [])


def make_lsp_range(location: SlangLocation) -> types.Range:
    return types.Range(
        make_lsp_position(location.begin), end=make_lsp_position(location.end)
    )


def make_lsp_position(location: SlangPosition) -> types.Position:
    return types.Position(location.row - 1, location.column - 1)


def make_slang_position(position: types.Position) -> SlangPosition:
    """Convert LSP position into Slang-lang position"""
    return SlangPosition(position.line + 1, position.character + 1)


def main():
    parser = argparse.ArgumentParser(description="Language server for Slang-Lang.")
    parser.add_argument("--port", type=int, default=8339)
    parser.add_argument("--tcp", help="Start a TCP server", action="store_true")
    parser.add_argument(
        "--stdio", help="Start a STDIO server (default)", action="store_true"
    )
    args = parser.parse_args()

    # Configure logging
    logging.getLogger("pygls").setLevel(logging.WARNING)
    logging.getLogger("slangc").setLevel(logging.INFO)
    # logging.getLogger("sllc").setLevel(logging.INFO)
    logformat = "%(asctime)s | %(levelname)8s | %(name)10.10s | %(message)s"
    # Note: basicConfig creates a logger writing to stderr
    # so it works even if we communicate via stdio
    logging.basicConfig(level=logging.DEBUG, format=logformat)
    logger.info("Starting slang-lang language server")

    if args.tcp:
        server.start_tcp("127.0.0.1", args.port)
    else:
        server.start_io()

    loop.run_until_complete(db.stop_validation())


if __name__ == "__main__":
    main()
