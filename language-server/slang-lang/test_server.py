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
\tlet x = foo(a: 5, b: 42)
\t# A nice place for a completion would be here:

\t0

fn foo(a: int, b: int) -> Position:
\tlet pos = Position()
\tpos.y = a - b
\tpos.up(amount: 5)
\tpos

class Position:
\tvar y: int = 0
\tfn up(amount: int):
\t\ty += amount

\tfn down():
\t\ty -= 1
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


@pytest.mark.timeout(20)
@pytest.mark.asyncio
async def test_doc_change_ok(client: LanguageClient):
    """Make a modification in the example code, re-triggering validation"""
    client.text_document_did_change(
        params=lsptypes.DidChangeTextDocumentParams(
            text_document=lsptypes.VersionedTextDocumentIdentifier(
                version=5, uri=example_uri
            ),
            content_changes=[
                lsptypes.TextDocumentContentChangeEvent_Type1(
                    lsptypes.Range(
                        start=lsptypes.Position(line=1, character=16),
                        end=lsptypes.Position(line=1, character=16),
                    ),
                    text="",
                )
            ],
        )
    )

    await client.wait_for_notification(lsptypes.TEXT_DOCUMENT_PUBLISH_DIAGNOSTICS)
    assert example_uri in client.diagnostics
    assert len(client.diagnostics[example_uri]) == 0


@pytest.mark.timeout(20)
@pytest.mark.asyncio
async def test_doc_change_error(client: LanguageClient):
    """Make a modification in the example code, triggering an unresolved name."""
    client.text_document_did_change(
        params=lsptypes.DidChangeTextDocumentParams(
            text_document=lsptypes.VersionedTextDocumentIdentifier(
                version=5, uri=example_uri
            ),
            content_changes=[
                lsptypes.TextDocumentContentChangeEvent_Type1(
                    lsptypes.Range(
                        start=lsptypes.Position(line=1, character=16),
                        end=lsptypes.Position(line=1, character=16),
                    ),
                    text="bla",
                )
            ],
        )
    )

    await client.wait_for_notification(lsptypes.TEXT_DOCUMENT_PUBLISH_DIAGNOSTICS)
    assert example_uri in client.diagnostics
    assert len(client.diagnostics[example_uri]) == 1
    assert client.diagnostics[example_uri][0].range.start.line == 1
    assert client.diagnostics[example_uri][0].range.start.character == 13
    assert client.diagnostics[example_uri][0].message == "Undefined symbol: intbla"


@pytest.mark.asyncio
async def test_signature_of_foo(client: LanguageClient):
    result = await client.text_document_signature_help_async(
        params=lsptypes.SignatureHelpParams(
            position=lsptypes.Position(line=2, character=13),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
            context=lsptypes.SignatureHelpContext(
                trigger_kind=lsptypes.SignatureHelpTriggerKind.TriggerCharacter,
                trigger_character="(",
                is_retrigger=False,
            ),
        )
    )

    assert len(result.signatures) > 0
    assert result.signatures[0].label == "foo(a: int, b: int) -> Position"
    assert result.signatures[0].parameters[0].label == "a"
    assert result.signatures[0].parameters[1].label == "b"


@pytest.mark.asyncio
async def test_signature_of_up_method(client: LanguageClient):
    result = await client.text_document_signature_help_async(
        params=lsptypes.SignatureHelpParams(
            position=lsptypes.Position(line=10, character=7),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
            context=lsptypes.SignatureHelpContext(
                trigger_kind=lsptypes.SignatureHelpTriggerKind.TriggerCharacter,
                trigger_character="(",
                is_retrigger=False,
            ),
        )
    )

    assert len(result.signatures) > 0
    assert result.signatures[0].label == "up(amount: int) -> void"
    assert result.signatures[0].parameters[0].label == "amount"


@pytest.mark.asyncio
async def test_invoked_completion(client: LanguageClient):
    """Retrieve completion suggestion."""
    result = await client.text_document_completion_async(
        params=lsptypes.CompletionParams(
            position=lsptypes.Position(line=5, character=23),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
            context=lsptypes.CompletionContext(
                trigger_kind=lsptypes.CompletionTriggerKind.Invoked,
            ),
        )
    )

    assert len(result.items) > 0
    assert result.items[0].label == "Position"
    # assert result.items[1].label == "foo"


@pytest.mark.asyncio
async def test_dot_completion(client: LanguageClient):
    """Retrieve completion suggestion after typing a '.' after 'pos'"""
    result = await client.text_document_completion_async(
        params=lsptypes.CompletionParams(
            position=lsptypes.Position(line=10, character=4),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
            context=lsptypes.CompletionContext(
                trigger_kind=lsptypes.CompletionTriggerKind.TriggerCharacter,
                trigger_character=".",
            ),
        )
    )

    assert len(result.items) > 0
    assert result.items[0].label == "down"
    assert result.items[1].label == "up"
    assert result.items[2].label == "y"


@pytest.mark.asyncio
async def test_go_to_definition(client: LanguageClient):
    """Test go to the definition of the 'up' method."""
    result = await client.text_document_definition_async(
        params=lsptypes.DefinitionParams(
            position=lsptypes.Position(line=10, character=6),
            text_document=lsptypes.TextDocumentIdentifier(uri=example_uri),
        )
    )

    assert result.uri == example_uri
    assert result.range.start.line == 15
    assert result.range.start.character == 4
    assert result.range.end.line == 15
    assert result.range.end.character == 6
