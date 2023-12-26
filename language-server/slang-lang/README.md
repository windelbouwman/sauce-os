# slang-lang Code extension

This is a Code extension to add support for slang-lang.

## Features

- Syntax highlighting
- Goto definition (F12)
- Diagnostics
- Symbol explorer

## Requirements

To use this extension, you need:

- python
- the [pygls package](https://github.com/openlawlibrary/pygls).
- The slang bootstrap compiler written in python [compiler1](../../compiler1/README.md)

## Installation

Build this extension using npm:

    $ npm install
    $ npm run compile

When this is done, create a symlink in your vs-code extension folder:

    $ ln --symbolic language-server/slang-lang ~/.vscode-oss/extensions

This allows you to modify the extension, and restart VS-Code to use the modified extension.

## Helix usage

To use the language server from the [helix editor](https://helix-editor.com/),
use the following configuration (.helix/languages.toml):

```
    [[language]]
    name = "slang"
    auto-format = false
    roots = []
    scope = "source.slang"
    file-types = ["slang"]
    comment-token = "#"
    indent = { tab-width = 4, unit = "    "}
    language-servers = [ "slang-lsp" ]

    [language-server.slang-lsp]
    command = "python"
    args = ["language-server/slang-lang/server.py"]
```

## Extension Settings

This extension contributes the following settings:

- `slang-lang.language-server-dev-mode`: Enable/disable dev mode. In dev-mode, the language client connects to a TCP socket instead of STDIO.
- `slang-lang.language-server-address`: The port to connect to when in dev-mode.
