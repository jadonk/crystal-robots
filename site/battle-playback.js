// Frame-log decoder and 60 fps player for a battle report from
// `battle()` (`./wasi-shim.js`): its `skeleton` (a static SVG, ids from
// `Battle.svg_skeleton`, `src/battle/svg_replay.cr`) and `frameBuffer`
// (this match's per-cycle frame log, `Browser.encode_frames`, layout
// documented in `src/browser.cr`). No framework, no CDN, same as every
// other page under `site/`.
//
// Phase 6 (ticket a83cd0a90f): before this, the in-page battle inserted
// one SMIL-animated SVG string and let the browser's own animation
// engine step through however many keyframes were recorded -- fine for
// the served `/battle` page's much smaller frame budget, but asking SMIL
// to interpolate tens of thousands of keyframes for the in-page battle's
// much larger one is exactly the slow, unresponsive rendering this phase
// exists to fix. Driving `requestAnimationFrame` ourselves means only the
// two frames bracketing "now" are ever touched, however long the log is,
// and gives room for play/pause, an adjustable speed and a scrubber,
// none of which a fire-and-forget SMIL animation could offer.
//
// Frame buffer layout (little-endian; mirrors `Browser.encode_frames`'s
// own doc comment in `src/browser.cr` exactly -- keep both in sync):
//   offset 0: u8  version
//   offset 1: u8  robotCount
//   offset 2: u16 missileSlots (per robot)
//   offset 4: u32 frameCount
//   offset 8: frameCount frames, each:
//     u32 cycle
//     robotCount robot records (12 bytes): i16 x, i16 y, i16 heading,
//       i16 scan, i16 cannon, u8 damage, u8 flags (bit0 active, bit1 fired)
//     robotCount*missileSlots missile records (6 bytes): i16 x, i16 y,
//       u8 flags (bit0 present, bit1 exploding), u8 padding
function decodeFrames(buffer) {
  const v = new DataView(buffer);
  const robotCount = v.getUint8(1);
  const missileSlots = v.getUint16(2, true);
  const frameCount = v.getUint32(4, true);
  const missileCount = robotCount * missileSlots;
  const robotStride = 12;
  const missileStride = 6;
  const frameStride = 4 + robotCount * robotStride + missileCount * missileStride;
  const frames = new Array(frameCount);
  let off = 8;
  for (let i = 0; i < frameCount; i++) {
    const cycle = v.getUint32(off, true);
    let p = off + 4;
    const robots = new Array(robotCount);
    for (let r = 0; r < robotCount; r++) {
      const x = v.getInt16(p, true);
      const y = v.getInt16(p + 2, true);
      const heading = v.getInt16(p + 4, true);
      const scan = v.getInt16(p + 6, true);
      const cannon = v.getInt16(p + 8, true);
      const damage = v.getUint8(p + 10);
      const flags = v.getUint8(p + 11);
      robots[r] = { x, y, heading, scan, cannon, damage, active: (flags & 1) !== 0, fired: (flags & 2) !== 0 };
      p += robotStride;
    }
    const missiles = new Array(missileCount);
    for (let m = 0; m < missileCount; m++) {
      const x = v.getInt16(p, true);
      const y = v.getInt16(p + 2, true);
      const flags = v.getUint8(p + 4);
      missiles[m] = { x, y, present: (flags & 1) !== 0, exploding: (flags & 2) !== 0 };
      p += missileStride;
    }
    frames[i] = { cycle, robots, missiles };
    off += frameStride;
  }
  return { robotCount, missileSlots, frames };
}

// Shortest signed delta from angle `a` to angle `b` (both 0..359), in
// (-180, 180] -- linear interpolation along this, rather than along the
// raw values, always turns the short way (`Battle.unwrap`'s job for the
// SMIL renderer's single big keyframe list; here each segment is handled
// independently, so no running total is needed).
function shortestDelta(a, b) {
  return (((b - a + 540) % 360) + 360) % 360 - 180;
}

// The largest frame index whose cycle is <= target.
function frameIndexAt(frames, target) {
  let lo = 0, hi = frames.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (frames[mid].cycle <= target) lo = mid; else hi = mid - 1;
  }
  return lo;
}

// Mounts a playback UI (svg + play/pause + speed + scrubber) into
// `container` from one `battle()` report. `initialCps` seeds the speed
// control. Returns `{ stop }` -- call it before replacing `container`'s
// contents with the next run's replay, so the previous match's animation
// loop does not keep running in the background.
export function mountBattlePlayback(container, report, initialCps) {
  const { robotCount, missileSlots, frames } = decodeFrames(report.frameBuffer);
  const totalCycles = frames.length ? frames[frames.length - 1].cycle : 0;

  container.innerHTML = "";

  const controls = document.createElement("div");
  controls.className = "battle-playback-controls";
  const playButton = document.createElement("button");
  playButton.type = "button";
  playButton.textContent = "Pause";
  const speedLabel = document.createElement("label");
  speedLabel.append("Speed, cycles/second ");
  const speedInput = document.createElement("input");
  speedInput.type = "number";
  speedInput.min = "1";
  speedInput.max = "50000";
  speedInput.step = "1";
  speedInput.value = String(initialCps);
  speedLabel.appendChild(speedInput);
  const scrubber = document.createElement("input");
  scrubber.type = "range";
  scrubber.min = "0";
  scrubber.max = String(Math.max(1, totalCycles));
  scrubber.step = "1";
  scrubber.value = "0";
  scrubber.className = "battle-scrubber";
  controls.append(playButton, " ", speedLabel, scrubber);
  container.appendChild(controls);

  const svgHost = document.createElement("div");
  svgHost.innerHTML = report.skeleton;
  container.appendChild(svgHost);
  const svg = svgHost.querySelector("svg");

  const robotEls = [];
  for (let i = 0; i < robotCount; i++) {
    robotEls.push({
      group: svg.getElementById(`robot-${i}`),
      scan: svg.getElementById(`scan-${i}`),
      body: svg.getElementById(`body-${i}`),
      heading: svg.getElementById(`heading-${i}`),
      cannon: svg.getElementById(`cannon-${i}`),
      trail: svg.getElementById(`trail-${i}`),
    });
  }
  const missileEls = [];
  for (let owner = 0; owner < robotCount; owner++) {
    for (let slot = 0; slot < missileSlots; slot++) {
      missileEls.push(svg.getElementById(`missile-${owner}-${slot}`));
    }
  }

  function trailPoint(i, f) {
    const pt = svg.createSVGPoint();
    pt.x = f.robots[i].x;
    pt.y = 1000 - f.robots[i].y;
    return pt;
  }

  function rebuildTrail(uptoInclusive) {
    for (let i = 0; i < robotCount; i++) {
      const trail = robotEls[i].trail;
      trail.points.clear();
      for (let idx = 0; idx <= uptoInclusive; idx++) trail.points.appendItem(trailPoint(i, frames[idx]));
    }
  }

  function extendTrail(fromExclusive, toInclusive) {
    for (let i = 0; i < robotCount; i++) {
      const trail = robotEls[i].trail;
      for (let idx = fromExclusive + 1; idx <= toInclusive; idx++) trail.points.appendItem(trailPoint(i, frames[idx]));
    }
  }

  let lastFrameIndex = -1;

  // Discrete (step-function) attributes: snap to the last frame reached,
  // same as `svg_animation`'s `calcMode="discrete"` -- a muzzle flash or
  // an explosion shows the instant its recorded frame is reached, not
  // interpolated toward.
  function renderDiscrete(index) {
    const f = frames[index];
    f.robots.forEach((r, i) => {
      const el = robotEls[i];
      el.scan.setAttribute("transform", `rotate(${-r.scan})`);
      el.body.setAttribute("opacity", r.active ? "1" : "0.3");
      el.cannon.setAttribute("transform", `rotate(${-r.cannon})`);
      el.cannon.setAttribute("opacity", r.fired ? "1" : "0");
    });
    f.missiles.forEach((m, k) => {
      const el = missileEls[k];
      if (!el) return;
      el.setAttribute("cx", String(m.x));
      el.setAttribute("cy", String(1000 - m.y));
      el.setAttribute("r", m.present ? (m.exploding ? "40" : "7") : "0");
      el.setAttribute("fill-opacity", m.present ? (m.exploding ? "0.25" : "1") : "0");
    });
    if (lastFrameIndex < 0 || index < lastFrameIndex) rebuildTrail(index);
    else if (index > lastFrameIndex) extendTrail(lastFrameIndex, index);
    lastFrameIndex = index;
  }

  // Continuous (linearly interpolated) attributes, every tick: position
  // and heading, so motion looks smooth at 60 fps even when the recorded
  // frames themselves are much sparser than that.
  function renderContinuous(index, t) {
    const lo = frames[index];
    const hi = frames[Math.min(index + 1, frames.length - 1)];
    lo.robots.forEach((r0, i) => {
      const r1 = hi.robots[i];
      const x = r0.x + (r1.x - r0.x) * t;
      const y = r0.y + (r1.y - r0.y) * t;
      const heading = r0.heading + shortestDelta(r0.heading, r1.heading) * t;
      robotEls[i].group.setAttribute("transform", `translate(${x} ${1000 - y})`);
      robotEls[i].heading.setAttribute("transform", `rotate(${-heading})`);
    });
  }

  let playing = frames.length > 1;
  let speed = Math.max(1, Number(speedInput.value) || initialCps || 1);
  let cycle = 0;
  let raf = null;
  let lastNow = null;

  function render() {
    const index = frameIndexAt(frames, cycle);
    if (index !== lastFrameIndex) renderDiscrete(index);
    const lo = frames[index];
    const hi = frames[Math.min(index + 1, frames.length - 1)];
    const span = hi.cycle - lo.cycle;
    const t = span > 0 ? (cycle - lo.cycle) / span : 0;
    renderContinuous(index, t);
    scrubber.value = String(Math.round(cycle));
  }

  function tick(now) {
    if (lastNow === null) lastNow = now;
    const dt = (now - lastNow) / 1000;
    lastNow = now;
    if (playing) {
      cycle = Math.min(totalCycles, cycle + dt * speed);
      if (cycle >= totalCycles) {
        playing = false;
        playButton.textContent = "Play";
      }
    }
    render();
    raf = requestAnimationFrame(tick);
  }

  playButton.addEventListener("click", () => {
    if (!playing && cycle >= totalCycles) cycle = 0;
    playing = !playing;
    playButton.textContent = playing ? "Pause" : "Play";
  });
  speedInput.addEventListener("input", () => {
    speed = Math.max(1, Number(speedInput.value) || 1);
  });
  scrubber.addEventListener("input", () => {
    cycle = Number(scrubber.value);
  });

  render();
  raf = requestAnimationFrame(tick);

  return {
    stop() {
      if (raf !== null) cancelAnimationFrame(raf);
    },
  };
}
