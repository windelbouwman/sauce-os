import fs from "fs";

let names = [];
for await (const file of fs.promises.glob("build/wasm/tests/test*.wasm")) {
  let parts = file.split("/");
  let name = parts[parts.length - 1].split(".")[0];
  names.push(name);
}

fs.writeFileSync(
  "build/webapp/meta-data.json",
  JSON.stringify({ tests: names }, null, 2),
);
