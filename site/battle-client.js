// One worker per match keeps compilation and the whole fight off the page.
export function battle(_module, robots, seed, limit, cps, { maxFrames } = {}) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(new URL("./battle-worker.js", import.meta.url), { type: "module" });
    worker.onmessage = ({ data }) => {
      worker.terminate();
      if (data.error) reject(new Error(data.error));
      else resolve(data.report);
    };
    worker.onerror = (event) => { worker.terminate(); reject(new Error(event.message)); };
    worker.postMessage({ robots, seed, limit, cps, maxFrames,
      engine: new URLSearchParams(location.search).get("engine") === "interpreter" ? "interpreter" : "compiled" });
  });
}
