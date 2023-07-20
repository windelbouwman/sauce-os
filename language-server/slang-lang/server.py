"""
Idea: start language server, to provide autocompletion and diagnostics in vs-code.

"""

import logging

from pygls.server import LanguageServer
from lsprotocol.types import (
    Diagnostic,
    DiagnosticSeverity,
    DidOpenTextDocumentParams,
    Position,
    Range,
    TEXT_DOCUMENT_COMPLETION,
    CompletionItem,
    CompletionList,
    CompletionParams,
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
    # ls.show_message(f"Document did open!: {params.text_document.uri}")
    text_doc = ls.workspace.get_document(params.text_document.uri)

    options = CompilationOptions()

    try:
        filename = params.text_document.uri.removeprefix("file://")
        do_compile([filename], None, options)
    except CompilationError as ex:
        diagnostics = []
        for filename, location, message in ex.errors:
            diagnostic = Diagnostic(
                range=Range(
                    start=Position(location.row - 1, location.column - 1),
                    end=Position(location.row - 1, location.column),
                ),
                severity=DiagnosticSeverity.Error,
                message=message,
            )
            diagnostics.append(diagnostic)
        ls.publish_diagnostics(text_doc.uri, diagnostics)


server.start_io()
