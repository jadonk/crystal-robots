import { battle, prepareRobotModules } from "./wasi-shim.js";
import { loadModule } from "./load-module.js";

self.onmessage = async ({ data }) => {
  try {
    const module = await loadModule();
    const engine = data.engine === "interpreter" ? "interpreter" : "compiled";
    const robotModules = engine === "compiled" ? await prepareRobotModules(module, data.robots) : [];
    const report = await battle(module, data.robots, data.seed, data.limit, data.cps, {
      maxFrames: data.maxFrames, engine, robotModules,
    });
    self.postMessage({ report }, report.frameBuffer ? [report.frameBuffer] : []);
  } catch (error) { self.postMessage({ error: error.message }); }
};
