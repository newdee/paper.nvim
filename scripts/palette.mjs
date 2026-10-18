// Vitesse's syntax colours on the paper backgrounds: each text colour moved
// in lightness only (its hue and saturation kept) until it reads at 4.5:1
// or more on every background text sits on (the editor, the cursor line,
// floats, the selection). Writes lua/paper/palette.lua; `--check` prints the ratios and fails
// when the file is not what this script writes.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
const hex2rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const rgb2hex = (c) => "#" + c.map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, "0")).join("");
const lin = (v) => ((v /= 255) <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
const lum = (h) => {
  const [r, g, b] = hex2rgb(h).map(lin);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const ratio = (a, b) => {
  const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
};
function toHsl([r, g, b]) {
  (r /= 255), (g /= 255), (b /= 255);
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h = 0, s = 0;
  const l = (max + min) / 2;
  if (max !== min) {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
    h /= 6;
  }
  return [h, s, l];
}
function fromHsl([h, s, l]) {
  if (s === 0) return [l, l, l].map((v) => v * 255);
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
  const f = (t) => {
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p + (q - p) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
    return p;
  };
  return [f(h + 1 / 3), f(h), f(h - 1 / 3)].map((v) => v * 255);
}
// Lighter on dark, darker on light, in steps of 0.5% lightness, until every
// background reads at `need` or more.
function fit(colour, bgs, need, dark) {
  let c = colour.toLowerCase();
  const worst = (x) => Math.min(...bgs.map((b) => ratio(x, b)));
  let [h, s, l] = toHsl(hex2rgb(c));
  while (worst(c) < need) {
    l += dark ? 0.005 : -0.005;
    if (l <= 0 || l >= 1) throw new Error(`${colour} cannot reach ${need}`);
    c = rgb2hex(fromHsl([h, s, l]));
  }
  return c;
}
const blend = (top, alpha, below) => rgb2hex(hex2rgb(top).map((v, i) => alpha * v + (1 - alpha) * hex2rgb(below)[i]));

const themes = {
  dark: {
    dark: true,
    // The board of a code block on dfine.tech at night, the page around it,
    // and keepane paper-dark's lines.
    ui: { bg: "#171716", bg_dim: "#121212", bg_hl: "#1f1f1e", bg_sel: "#2b2b29", bg_float: "#121212", line: "#2b2b29", border: "#666664" },
    ink: { fg: "#dbd7ca", soft: "#a5a29a", muted: "#87837b", faint: "#666664", cinnabar: "#dd625e" },
    syntax: {
      comment: "#758575", punct: "#666666", constant: "#c99076", func: "#80a665", keyword: "#4d9375",
      builtin: "#cb7676", string: "#c98a7d", property: "#b8a965", variable: "#bd976a", type: "#5da994",
      namespace: "#db889a", regex: "#c4704f", number: "#4c9a91", class: "#6872ab", quote: "#5d99a9",
      escape: "#e6cc77", heading: "#4d9375",
      error: "#cb7676", warn: "#d4976c", info: "#6394bf", hint: "#4d9375",
      add: "#4d9375", change: "#6394bf", delete: "#cb7676", yellow: "#e6cc77", magenta: "#d9739f",
    },
    // keepane paper-dark's pane-colours, for :terminal.
    terminal: "#393a34 #cb7676 #4d9375 #e6cc77 #6394bf #d9739f #5eaab5 #dbd7ca #818181 #cb7676 #4d9375 #e6cc77 #6394bf #d9739f #5eaab5 #ffffff",
  },
  light: {
    dark: false,
    // The white board of a code block by day, its rail, keepane paper's lines.
    ui: { bg: "#fdfdfb", bg_dim: "#eceae4", bg_hl: "#f4f2ee", bg_sel: "#e4e2dc", bg_float: "#f6f5f1", line: "#e4e2dc", border: "#92908a" },
    ink: { fg: "#393a34", soft: "#5d5b55", muted: "#6b6860", faint: "#92908a", cinnabar: "#b83e3c" },
    syntax: {
      comment: "#a0ada0", punct: "#999999", constant: "#a65e2b", func: "#59873a", keyword: "#1e754f",
      builtin: "#ab5959", string: "#b56959", property: "#998418", variable: "#b07d48", type: "#2e8f82",
      namespace: "#b05a78", regex: "#ab5e3f", number: "#2f798a", class: "#5a6aa6", quote: "#2e808f",
      escape: "#bda437", heading: "#1c6b48",
      error: "#ab5959", warn: "#a65e2b", info: "#296aa3", hint: "#1e754f",
      add: "#1e754f", change: "#296aa3", delete: "#ab5959", yellow: "#776723", magenta: "#a13865",
    },
    // keepane paper's pane-colours.
    terminal: "#eceae4 #9e5252 #1e754f #776723 #296aa3 #a13865 #20727e #5d5b55 #6a6863 #9e5252 #1e754f #776723 #296aa3 #a13865 #20727e #393a34",
  },
};

const out = {};
const report = [];
for (const [name, t] of Object.entries(themes)) {
  // The selection too: syntax shows through Visual, and the chosen item of a menu is text on it.
  const textBgs = [t.ui.bg, t.ui.bg_hl, t.ui.bg_float, t.ui.bg_dim, t.ui.bg_sel];
  const p = { ...t.ui };
  for (const [k, v] of Object.entries(t.ink)) {
    // Line numbers and borders are lines, not reading text: 3:1. The
    // cinnabar as text is `accent`; `cinnabar` itself stays the exact
    // colour of keepane and the blog, for blocks with on_accent on them.
    const key = k === "cinnabar" ? "accent" : k;
    const need = k === "faint" ? 3 : 4.5;
    p[key] = fit(v, k === "faint" ? [t.ui.bg] : textBgs, need, t.dark);
    report.push([name, key, v, p[key], Math.min(...(k === "faint" ? [t.ui.bg] : textBgs).map((b) => ratio(p[key], b))).toFixed(2)]);
  }
  p.cinnabar = t.ink.cinnabar;
  for (const [k, v] of Object.entries(t.syntax)) {
    p[k] = fit(v, textBgs, 4.5, t.dark);
    report.push([name, k, v, p[k], Math.min(...textBgs.map((b) => ratio(p[k], b))).toFixed(2)]);
  }
  p.border = fit(t.ui.border, [t.ui.bg, t.ui.bg_float], 3, t.dark);
  // Washes behind text: search, diff lines, the matching bracket. Text on
  // them keeps 4.5:1 (checked below with the real fg).
  // Vitesse's find-match yellow, as a wash.
  p.search = blend("#e6cc77", t.dark ? 0.22 : 0.4, t.ui.bg);
  p.diff_add = blend(p.add, t.dark ? 0.16 : 0.12, t.ui.bg);
  p.diff_delete = blend(p.delete, t.dark ? 0.12 : 0.12, t.ui.bg);
  p.diff_change = blend(p.change, t.dark ? 0.14 : 0.1, t.ui.bg);
  p.diff_text = blend(p.change, t.dark ? 0.3 : 0.22, t.ui.bg);
  p.match = blend(p.keyword, t.dark ? 0.25 : 0.18, t.ui.bg);
  p.cinnabar_soft = blend(p.cinnabar, t.dark ? 0.15 : 0.1, t.ui.bg);
  for (const w of ["search", "diff_add", "diff_delete", "diff_change", "diff_text", "match", "cinnabar_soft", "bg_sel"])
    report.push([name, `fg on ${w}`, "", p[w], ratio(p.fg, p[w]).toFixed(2)]);
  // Text on a cinnabar block (the current match, the mode on the bar), as
  // keepane draws the session's name.
  p.on_accent = t.dark ? t.ui.bg_dim : t.ui.bg;
  report.push([name, "on_accent", "", p.on_accent, ratio(p.on_accent, p.cinnabar).toFixed(2)]);
  p.terminal = t.terminal.split(" ");
  out[name] = p;
}
const lua = (name, p) =>
  `  ${name} = {\n` +
  Object.entries(p)
    .map(([k, v]) => (Array.isArray(v) ? `    ${k} = { ${v.map((x) => `"${x}"`).join(", ")} },` : `    ${k} = "${v}",`))
    .join("\n") +
  "\n  },";
const file =
  "-- Generated by scripts/palette.mjs from Vitesse's colours on paper: edit\n" +
  "-- that script, not this file (`node scripts/palette.mjs`).\nreturn {\n" +
  lua("dark", out.dark) + "\n" + lua("light", out.light) + "\n}\n";
const target = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "lua", "paper", "palette.lua");
for (const r of report) console.log(r.map((x) => String(x).padEnd(14)).join(""));
if (process.argv.includes("--check")) {
  const now = fs.existsSync(target) ? fs.readFileSync(target, "utf8").replace(/\r\n/g, "\n") : "";
  if (now !== file) {
    console.error("lua/paper/palette.lua is not what scripts/palette.mjs writes: run `node scripts/palette.mjs`");
    process.exit(1);
  }
  console.log("palette.lua is up to date");
} else {
  fs.writeFileSync(target, file);
  console.log("wrote " + target);
}