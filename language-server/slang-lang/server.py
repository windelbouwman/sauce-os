"""
Idea: start language server, to provide autocompletion and diagnostics in vs-code.

"""

import logging
import time

from pygls.server import LanguageServer
from lsprotocol.types import (
    Diagnostic,
    DiagnosticSeverity,
    DidOpenTextDocumentParams,
    Position,
    Range,
    TEXT_DOCUMENT_COMPLETION,
    TEXT_DOCUMENT_DID_CHANGE,
    CompletionItem,
    CompletionList,
    CompletionParams,
    DidChangeTextDocumentParams,
    TEXT_DOCUMENT_DID_OPEN,
)

import sys, os

sys.path.append(os.path.join(os.path.dirname(__file__), "..", ".."))
from compiler1.compiler import do_compile, CompilationOptions
from compiler1.errors import CompilationError

logging.basicConfig(level=logging.DEBUG)
server = LanguageServer("Slang-Lang-Server", "v0.1")


@server.feature(TEXT_DOCUMENT_COMPLETION)
def completions(params: CompletionParams) -> CompletionList:
    # items = []
    # document = server.workspace.get_document(params.text_document.uri)
    # current_line = document.lines[params.position.line].strip()
    # if current_line.endswith("hello."):
    items = [
        CompletionItem(label="world"),
        CompletionItem(label="hello"),
        CompletionItem(label="TODO"),
    ]
    return CompletionList(is_incomplete=False, items=items)


@server.feature(TEXT_DOCUMENT_DID_OPEN)
def did_open(ls: LanguageServer, params: DidOpenTextDocumentParams):
    _validate(ls, params)


@server.feature(TEXT_DOCUMENT_DID_CHANGE)
def did_change(ls, params: DidChangeTextDocumentParams):
    _validate(ls, params)


def _validate(ls: LanguageServer, params):
    text_doc = ls.workspace.get_document(params.text_document.uri)

    options = CompilationOptions()
    # time.sleep(2)

    diagnostics = []
    try:
        filename = text_doc.uri.removeprefix("file://")
        code = text_doc.source
        # TODO: figure out how to deal with a folder of files.
        do_compile([(filename, code)], None, options)
    except CompilationError as ex:
        for filename, location, message in ex.errors:
            diagnostic = Diagnostic(
                range=make_range(location),
                severity=DiagnosticSeverity.Error,
                message=message,
            )
            diagnostics.append(diagnostic)
    ls.publish_diagnostics(text_doc.uri, diagnostics)


def make_range(location) -> Range:
    return Range(make_position(location.begin), end=make_position(location.end))


def make_position(location) -> Position:
    return Position(location.row - 1, location.column - 1)


do_tcp = False
if do_tcp:
    server.start_tcp("127.0.0.1", 8339)
else:
    server.start_io()
