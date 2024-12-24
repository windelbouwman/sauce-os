"""Test script for slang lang language server

This works by starting server.py as language server.
Then give the server commands using the pytest-lsp library.
"""

import sys
import os
import pytest
import pytest_lsp
import lsprotocol.types as lsptypes
from pytest_lsp import ClientServerConfig, LanguageClient

server_script = os.path.abspath(os.path.join(os.path.dirname(__file__), "server.py"))

example_uri = "file:///snippets/example.slang"
example_source = """
fn main() -> int:
    let x = foo(a: 5, b: 42)
    # A nice place for a completion would be here:

    0

fn foo(a: int, b: int) -> int:
    let p = Position()
    a - b

class Position:
    var y: int = 0
    fn up():
        y += 1

    fn down():
        y -= 1
"""


@pytest_lsp.fixture(
    config=ClientServerConfig(
        server_command=[sys.executable, server_script],
    ),
)
async def client(lsp_client: LanguageClient):
    params = lsptypes.InitializeParams(capabilities=lsptypes.ClientCapabilities())
    await lsp_client.initialize_session(params)

    # Open example document
    lsp_client.text_document_did_open(
        lsptypes.DidOpenTextDocumentParams(
            text_document=lsptypes.TextDocumentItem(
                uri=example_uri,
                language_id="plaintext",
                version=1,
                text=example_source,
            )
        )
    )

    # Check example is valid slang-lang code.
    await lsp_client.wait_for_notification(lsptypes.TEXT_DOCUMENT_PUBLISH_DIAGNOSTICS)
    assert example_uri in lsp_client.diagnostics
    assert len(lsp_client.diagnostics[example_uri]) == 0

    yield

    # Close example document
    lsp_client.text_document_did_close(
        lsptypes.DidCloseTextDocumentParams(
            text_document=lsptypes.TextDocumentIdentifier(
                uri=example_uri,
            )
        )
    )

    await lsp_client.shutdown_session()


@pytest.mark.asyncio
async def test_signature_of_foo(client: LanguageClient):
    result = await client.text_document_signature_help_async(
        params=lsptypes.SignatureHelpParams(
            position=lsptypes.Position(line=2, character=15),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
        )
    )

    assert len(result.signatures) > 0
    assert result.signatures[0].label == "foo(a: int, b: int) -> int"
    assert result.signatures[0].parameters[0].label == "a"
    assert result.signatures[0].parameters[1].label == "b"


@pytest.mark.asyncio
async def test_completion_in_example(client: LanguageClient):
    # Retrieve completion suggestion:
    result = await client.text_document_completion_async(
        params=lsptypes.CompletionParams(
            position=lsptypes.Position(line=5, character=23),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
        )
    )

    assert len(result.items) > 0
    assert result.items[0].label == "main"
    assert result.items[1].label == "foo"
