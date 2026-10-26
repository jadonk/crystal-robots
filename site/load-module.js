export async function loadModule() {
  const response = await fetch(new URL("./crystal-robots.wasm", import.meta.url));
  if (!response.ok) throw new Error(`fetch crystal-robots.wasm: ${response.status}`);
  try { return await WebAssembly.compileStreaming(response.clone()); }
  catch { return WebAssembly.compile(await response.arrayBuffer()); }
}
