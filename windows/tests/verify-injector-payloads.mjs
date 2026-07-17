import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const injectors = [
  path.resolve(here, "../scripts/injector.mjs"),
  path.resolve(here, "../../macos/scripts/injector.mjs"),
];
const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dream-skin-payload-tests-"));

function run(injector, args) {
  return spawnSync(process.execPath, [injector, ...args], {
    encoding: "utf8",
    timeout: 8000,
    maxBuffer: 4 * 1024 * 1024,
  });
}

function expectSuccess(injector, args, label) {
  const result = run(injector, args);
  assert.equal(result.status, 0, `${label}: ${result.stderr || result.stdout}`);
}

function expectFailure(injector, args, label) {
  const result = run(injector, args);
  assert.notEqual(result.status, 0, `${label} unexpectedly succeeded`);
  assert.notEqual(result.error?.code, "ETIMEDOUT", `${label} hung`);
}

function createTheme(name, theme, imageName = "background.png", size = 1) {
  const directory = path.join(temporaryRoot, name);
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, "theme.json"), `${JSON.stringify(theme)}\n`);
  if (imageName && path.basename(imageName) === imageName) {
    const image = path.join(directory, imageName);
    const handle = fs.openSync(image, "w");
    fs.ftruncateSync(handle, size);
    fs.closeSync(handle);
  }
  return directory;
}

try {
  const valid = createTheme("valid", { schemaVersion: 1, image: "background.png", name: "Test" });
  const badSchema = createTheme("bad-schema", { schemaVersion: 2, image: "background.png" });
  const traversal = createTheme("traversal", { schemaVersion: 1, image: "../background.png" }, null);
  const empty = createTheme("empty", { schemaVersion: 1, image: "background.png" }, "background.png", 0);
  const oversized = createTheme(
    "oversized",
    { schemaVersion: 1, image: "background.png" },
    "background.png",
    16 * 1024 * 1024 + 1,
  );
  const unsupported = createTheme("unsupported", { schemaVersion: 1, image: "background.gif" }, "background.gif");

  for (const injector of injectors) {
    expectSuccess(injector, ["--check-payload", "--theme-dir", valid], `${injector} valid theme`);
    expectFailure(injector, ["--check-payload", "--theme-dir", badSchema], `${injector} schema rejection`);
    expectFailure(injector, ["--check-payload", "--theme-dir", traversal], `${injector} traversal rejection`);
    expectFailure(injector, ["--check-payload", "--theme-dir", empty], `${injector} empty image rejection`);
    expectFailure(injector, ["--check-payload", "--theme-dir", oversized], `${injector} oversized image rejection`);
    expectFailure(injector, ["--check-payload", "--theme-dir", unsupported], `${injector} format rejection`);
    expectFailure(injector, ["--verify", "--port", "80"], `${injector} port rejection`);
  }
  console.log("Injector payload validation passed for Windows and macOS invalid schema, path, size, format, and port cases.");
} finally {
  fs.rmSync(temporaryRoot, { recursive: true, force: true });
}
