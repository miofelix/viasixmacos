import { connect } from "cloudflare:sockets";

const USER_ID = "00000000-0000-4000-8000-000000000000";
const WS_OPEN = 1;
const WS_CLOSING = 2;
const MAX_HEADER_BYTES = 4096;
const textDecoder = new TextDecoder();

export default {
  async fetch(request, env) {
    const configuredUserID = String(env.uuid || USER_ID).trim().toLowerCase();
    if (!isValidUUID(configuredUserID)) {
      return new Response("Server configuration error", { status: 500 });
    }

    const upgrade = request.headers.get("Upgrade")?.toLowerCase();
    if (upgrade === "websocket") {
      return createVLESSWebSocket(request, configuredUserID);
    }

    return handleHTTP(request, configuredUserID);
  },
};

function handleHTTP(request, userID) {
  const url = new URL(request.url);
  const host = url.hostname;

  if (url.pathname === `/${userID}/pcl`) {
    return new Response(mihomoConfiguration(host, userID), {
      headers: {
        "Cache-Control": "no-store",
        "Content-Type": "text/yaml; charset=utf-8",
      },
    });
  }

  if (url.pathname === `/${userID}`) {
    const body = [
      "ViaSix Cloudflare Pages",
      "",
      `Mihomo: https://${host}/${userID}/pcl`,
      "",
      "Transport: VLESS + WebSocket + TLS",
      "WebSocket path: /?ed=2560",
      "Upstream mode: direct TCP",
    ].join("\n");
    return new Response(body, {
      headers: {
        "Cache-Control": "no-store",
        "Content-Type": "text/plain; charset=utf-8",
      },
    });
  }

  return new Response("ViaSix Cloudflare Pages is running.", {
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "text/plain; charset=utf-8",
    },
  });
}

function createVLESSWebSocket(request, userID) {
  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair);
  server.accept();

  const state = {
    closed: false,
    headerBuffer: new Uint8Array(0),
    initialized: false,
    queue: Promise.resolve(),
    remoteSocket: null,
    remoteWriter: null,
    responseHeader: null,
  };

  const closeSession = () => {
    if (state.closed) return;
    state.closed = true;

    try {
      state.remoteWriter?.releaseLock();
    } catch {}
    state.remoteWriter = null;

    try {
      state.remoteSocket?.close();
    } catch {}
    state.remoteSocket = null;

    safeCloseWebSocket(server);
  };

  const enqueue = (data) => {
    state.queue = state.queue
      .then(async () => {
        if (state.closed) return;
        const chunk = await toUint8Array(data);
        if (chunk.byteLength === 0) return;
        await handleClientChunk(chunk, state, userID, server, closeSession);
      })
      .catch((error) => {
        console.error("VLESS session error:", safeErrorMessage(error));
        closeSession();
      });
  };

  server.addEventListener("message", (event) => enqueue(event.data));
  server.addEventListener("close", closeSession);
  server.addEventListener("error", closeSession);

  const earlyData = decodeEarlyData(request.headers.get("Sec-WebSocket-Protocol"));
  if (earlyData?.byteLength) enqueue(earlyData);

  return new Response(null, {
    status: 101,
    webSocket: client,
  });
}

async function handleClientChunk(chunk, state, userID, webSocket, closeSession) {
  if (state.initialized) {
    if (!state.remoteWriter) throw new Error("Remote TCP writer is unavailable");
    await state.remoteWriter.write(chunk);
    return;
  }

  state.headerBuffer = concatBytes(state.headerBuffer, chunk);
  if (state.headerBuffer.byteLength > MAX_HEADER_BYTES) {
    throw new Error("VLESS request header is too large");
  }

  const parsed = parseVLESSRequest(state.headerBuffer, userID);
  if (parsed.incomplete) return;
  if (parsed.error) throw new Error(parsed.error);
  if (parsed.command !== 1) {
    throw new Error("Only VLESS TCP commands are supported");
  }

  state.initialized = true;
  state.responseHeader = new Uint8Array([parsed.version, 0]);
  const initialPayload = state.headerBuffer.slice(parsed.payloadOffset);
  state.headerBuffer = new Uint8Array(0);

  const remoteSocket = connect({
    hostname: parsed.address,
    port: parsed.port,
  });
  state.remoteSocket = remoteSocket;
  state.remoteWriter = remoteSocket.writable.getWriter();

  void remoteSocket.closed
    .catch((error) => {
      if (!state.closed) {
        console.error("Remote TCP close error:", safeErrorMessage(error));
      }
    })
    .finally(closeSession);

  void pumpRemoteToWebSocket(remoteSocket, state, webSocket, closeSession);

  if (initialPayload.byteLength > 0) {
    await state.remoteWriter.write(initialPayload);
  }
}

async function pumpRemoteToWebSocket(remoteSocket, state, webSocket, closeSession) {
  const reader = remoteSocket.readable.getReader();
  try {
    while (!state.closed) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value?.byteLength) continue;
      if (webSocket.readyState !== WS_OPEN) break;

      if (state.responseHeader) {
        webSocket.send(concatBytes(state.responseHeader, value).buffer);
        state.responseHeader = null;
      } else {
        webSocket.send(value);
      }
    }
  } catch (error) {
    if (!state.closed) {
      console.error("Remote TCP read error:", safeErrorMessage(error));
    }
  } finally {
    try {
      reader.releaseLock();
    } catch {}
    closeSession();
  }
}

function parseVLESSRequest(buffer, expectedUserID) {
  if (buffer.byteLength < 19) return { incomplete: true };

  const version = buffer[0];
  if (!uuidBytesMatch(buffer.slice(1, 17), expectedUserID)) {
    return { error: "Invalid VLESS user" };
  }

  const optionLength = buffer[17];
  const commandIndex = 18 + optionLength;
  if (buffer.byteLength < commandIndex + 4) return { incomplete: true };

  const command = buffer[commandIndex];
  const portIndex = commandIndex + 1;
  const port = (buffer[portIndex] << 8) | buffer[portIndex + 1];
  const addressTypeIndex = portIndex + 2;
  const addressType = buffer[addressTypeIndex];
  let addressIndex = addressTypeIndex + 1;
  let addressLength;
  let address;

  if (addressType === 1) {
    addressLength = 4;
    if (buffer.byteLength < addressIndex + addressLength) return { incomplete: true };
    address = Array.from(buffer.slice(addressIndex, addressIndex + addressLength)).join(".");
  } else if (addressType === 2) {
    if (buffer.byteLength < addressIndex + 1) return { incomplete: true };
    addressLength = buffer[addressIndex];
    addressIndex += 1;
    if (addressLength === 0) return { error: "VLESS domain is empty" };
    if (buffer.byteLength < addressIndex + addressLength) return { incomplete: true };
    address = textDecoder.decode(buffer.slice(addressIndex, addressIndex + addressLength));
  } else if (addressType === 3) {
    addressLength = 16;
    if (buffer.byteLength < addressIndex + addressLength) return { incomplete: true };
    const groups = [];
    for (let index = 0; index < 16; index += 2) {
      groups.push(((buffer[addressIndex + index] << 8) | buffer[addressIndex + index + 1]).toString(16));
    }
    address = groups.join(":");
  } else {
    return { error: "Unsupported VLESS address type" };
  }

  if (!address || port < 1 || port > 65535) {
    return { error: "Invalid VLESS destination" };
  }

  return {
    address,
    command,
    incomplete: false,
    payloadOffset: addressIndex + addressLength,
    port,
    version,
  };
}

function uuidBytesMatch(bytes, uuid) {
  if (bytes.byteLength !== 16) return false;
  const expected = uuid.replaceAll("-", "");
  for (let index = 0; index < bytes.byteLength; index += 1) {
    const value = bytes[index].toString(16).padStart(2, "0");
    if (value !== expected.slice(index * 2, index * 2 + 2)) return false;
  }
  return true;
}

async function toUint8Array(value) {
  if (value instanceof Uint8Array) return value;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) {
    return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  }
  if (value && typeof value.arrayBuffer === "function") {
    return new Uint8Array(await value.arrayBuffer());
  }
  throw new Error("Unsupported WebSocket frame type");
}

function concatBytes(first, second) {
  const left = first instanceof Uint8Array ? first : new Uint8Array(first);
  const right = second instanceof Uint8Array ? second : new Uint8Array(second);
  const combined = new Uint8Array(left.byteLength + right.byteLength);
  combined.set(left, 0);
  combined.set(right, left.byteLength);
  return combined;
}

function decodeEarlyData(value) {
  if (!value) return null;
  try {
    let normalized = value.replaceAll("-", "+").replaceAll("_", "/");
    normalized += "=".repeat((4 - (normalized.length % 4)) % 4);
    const decoded = atob(normalized);
    return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
  } catch {
    return null;
  }
}

function safeCloseWebSocket(webSocket) {
  try {
    if (webSocket.readyState === WS_OPEN || webSocket.readyState === WS_CLOSING) {
      webSocket.close(1000, "Session closed");
    }
  } catch {}
}

function safeErrorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

function isValidUUID(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function mihomoConfiguration(host, userID) {
  return [
    "x-viasix:",
    "  version: 1",
    "  primary-server: selected-ip",
    "  routing-mode: rule",
    "  udp-enabled: false",
    "  log-level: info",
    "  sniffing-enabled: true",
    "  bypass-private-networks: true",
    "proxies:",
    "  - name: ViaSix Cloudflare Pages",
    "    type: vless",
    "    port: 443",
    `    uuid: ${userID}`,
    "    encryption: none",
    "    udp: false",
    "    tls: true",
    `    servername: ${host}`,
    "    client-fingerprint: chrome",
    "    skip-cert-verify: false",
    "    network: ws",
    "    ws-opts:",
    '      path: "/?ed=2560"',
    "      headers:",
    `        Host: ${host}`,
    "",
  ].join("\n");
}
