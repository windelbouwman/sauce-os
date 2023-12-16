import { ExtensionContext, workspace } from "vscode";
import * as path from "path";
import * as net from "net";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient;

export function activate(context: ExtensionContext) {
  // Whether or not to start the python server itself

  // context.workspaceState.
  const devMode: boolean = workspace
    .getConfiguration("slang-lang")
    .get("language-server-dev-mode");

  let serverOptions: ServerOptions;
  if (devMode) {
    serverOptions = () => {
      return new Promise((resolve /*, reject */) => {
        const clientSocket = new net.Socket();
        const port = 8339;
        clientSocket.connect(port, "127.0.0.1", () => {
          resolve({
            reader: clientSocket,
            writer: clientSocket,
          });
        });
      });
    };
  } else {
    const pythonPath = workspace
      .getConfiguration("python")
      .get<string>("defaultInterpreterPath");
    if (!pythonPath) {
      throw new Error("`python.defaultInterpreterPath` is not set");
    }

    const cwd = path.join(__dirname, "..");

    serverOptions = {
      command: pythonPath,
      args: ["server.py"],
      options: {
        cwd: cwd,
      },
      transport: TransportKind.stdio,
    };
  }

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
