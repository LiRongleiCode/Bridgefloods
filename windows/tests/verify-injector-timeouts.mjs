import assert from "node:assert/strict";
import crypto from "node:crypto";
import http from "node:http";
import path from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const injector = path.resolve(here, "../scripts/injector.mjs");

async function runTimeoutScenario(mode) {
  const sockets = new Set();
  const server = http.createServer((request, response) => {
    if (request.url !== "/json/list") {
      response.writeHead(404).end();
      return;
    }
    const { port } = server.address();
    response.setHeader("content-type", "application/json");
    response.end(JSON.stringify([{
      id: "test-page",
      type: "page",
      title: "Codex timeout test",
      url: "app://codex/index.html",
      webSocketDebuggerUrl: `ws://127.0.0.1:${port}/devtools/page/test-page`,
    }]));
  });
  server.on("connection", (socket) => {
    sockets.add(socket);
    socket.on("error", () => {});
    socket.on("close", () => sockets.delete(socket));
  });
  server.on("upgrade", (request, socket) => {
    if (mode === "open") return;
    const key = request.headers["sec-websocket-key"];
    const accept = crypto
      .createHash("sha1")
      .update(`${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`)
      .digest("base64");
    socket.write([
      "HTTP/1.1 101 Switching Protocols",
      "Upgrade: websocket",
      "Connection: Upgrade",
      `Sec-WebSocket-Accept: ${accept}`,
      "",
      "",
    ].join("\r\n"));
  });

  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const { port } = server.address();
  const child = spawn(process.execPath, [
    injector, "--verify", "--port", String(port), "--timeout-ms", "1200",
  ], { stdio: ["ignore", "pipe", "pipe"] });
  let stderr = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { stderr += chunk; });

  const result = await Promise.race([
    new Promise((resolve) => child.once("exit", (code, signal) => resolve({ code, signal }))),
    new Promise((resolve) => setTimeout(() => resolve({ timedOut: true }), 7000)),
  ]);
  if (result.timedOut) child.kill("SIGKILL");

  for (const socket of sockets) socket.destroy();
  await new Promise((resolve) => server.close(resolve));

  assert.equal(result.timedOut, undefined, `${mode} timeout scenario hung`);
  assert.notEqual(result.code, 0, `${mode} timeout scenario unexpectedly succeeded`);
  const expected = mode === "open"
    ? "CDP WebSocket open timed out"
    : "CDP command timed out: Runtime.enable";
  assert.match(stderr, new RegExp(expected.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
}

await runTimeoutScenario("open");
await runTimeoutScenario("command");
console.log("Injector timeout behavior passed: WebSocket open and CDP command stalls exit cleanly.");
