import { ExtensionContext, workspace } from "vscode";
import * as path from "path";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient;

export function activate(context: ExtensionContext) {
  const pythonPath = workspace
    .getConfiguration("python")
    .get<string>("defaultInterpreterPath");
  if (!pythonPath) {
    throw new Error("`python.defaultInterpreterPath` is not set");
  }

  const cwd = path.join(__dirname, "..");

  const serverOptions: ServerOptions = {
    command: pythonPath,
    args: ["server.py"],
    options: {
      cwd: cwd,
    },
    transport: TransportKind.stdio,
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "slang" }],
  };

  client = new LanguageClient(
    "slang-lang",
    "Slang-Lang",
    serverOptions,
    clientOptions
  );

  client.start();
}

export function deactivate() {
  if (!client) {
    return undefined;
  }
  return client.stop();
}
