import { tournament, prepareRobotModules } from "../wasi-shim.js";
import { loadModule } from "../load-module.js";
self.onmessage = async ({ data }) => {
  try {
    self.postMessage({ progress: "Compiling the arena…" });
    const module = await loadModule();
    self.postMessage({ progress: "Playing pools and bracket…" });
    const engine = data.engine === "interpreter" ? "interpreter" : "compiled";
    const robotModules = engine === "compiled" ? await prepareRobotModules(module, data.robots) : [];
    const report = await tournament(module, data.robots, data.seed, data.limit, { engine, robotModules });
    self.postMessage({ report });
  } catch (error) { self.postMessage({ error: error.message }); }
};
