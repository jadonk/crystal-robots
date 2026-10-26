export const SOURCE_KEY = "crystal-robots:your-source";
export const PROGRESS_KEY = "crystal-robots:challenge-progress";
export function loadSavedSource() { try { return localStorage.getItem(SOURCE_KEY) || ""; } catch { return ""; } }
export function saveSource(source) { try { localStorage.setItem(SOURCE_KEY, source); } catch {} }
export function loadProgress() { try { return JSON.parse(localStorage.getItem(PROGRESS_KEY) || "{}") || {}; } catch { return {}; } }
export function saveProgress(progress) { try { localStorage.setItem(PROGRESS_KEY, JSON.stringify(progress)); } catch {} }
