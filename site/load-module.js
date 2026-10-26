export async function loadModule() {
  const response = await fetch("../crystal-robots.wasm");
  if (!response.ok) throw new Error(`fetch crystal-robots.wasm: ${response.status}`);
  try { return await WebAssembly.compileStreaming(response.clone()); }
  catch { return WebAssembly.compile(await response.arrayBuffer()); }
}
