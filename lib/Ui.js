.pragma library

// Pure helpers for the overlay's view: the welcome checklist, card placement,
// key caps, Omi's mode and gaze, idle hints, display probes and what
// "Do it for me" runs. Kept out of QML so node can test them.

// After 40 s without progress the key-cap hint grows and Omi nudges; after
// a minute the overlay offers "Do it for me".
var HINT_AFTER_MS = 40000;
var DO_IT_AFTER_MS = 60000;

// The line the clipboard step prints in a terminal for the user to copy and paste.
var CLIPBOARD_SAMPLE = "Omarchy copies and pastes the same way everywhere";
// That terminal's app id (window class), so onboarding can close it, and only
// it, once the step is over. It must stay under org.omarchy.: Omarchy tags
// those as terminals (default/hypr/apps/terminals.lua), and Super + C / V only
// copy and paste in a window tagged terminal.
var SAMPLE_APP_ID = "org.omarchy.onboarding-sample";

// Steps shown as a centered card that takes the keyboard. Every other step
// is a small card in the corner that leaves the keyboard to Hyprland, so
// Super shortcuts and the panels they open always reach it.
var CENTERED_STEPS = ["welcome", "super-key", "finish"];

// When a step finishes by itself, the card stays this long so Omi's success
// (its morph and the pack's hold, about 2 s) plays on it, with every
// sub-task ticked, before the next.
var CELEBRATE_MS = 2000;

// 0: plain, 1: bigger key caps, 2: also offer "Do it for me".
function hintLevel(idleMs) {
    if (idleMs >= DO_IT_AFTER_MS) return 2;
    if (idleMs >= HINT_AFTER_MS) return 1;
    return 0;
}

// What Omi says in place of the card's title while the user is stalled
// (the same place its cheer appears when a step is done): after 40 s a
// nudge, after a minute the offer to do it, when the step has a "Do it for me".
// "" when there is nothing to say.
function omiHint(stepId, hint, canDoIt) {
    if (hint >= 2 && canDoIt) return "Stuck? I can do it.";
    if (hint >= 1) return stepId === "super-key" ? "Look on the bottom row, left of the space bar, next to Alt." : "Take your time. The keys are right here.";
    return "";
}

function isCentered(stepId) {
    return CENTERED_STEPS.indexOf(stepId) >= 0;
}

// Where the corner card sits, out of the way of what each step shows:
//   bottom-right   by default: menus, the keybindings list and the theme
//                  picker open in the middle, panels open from the bar
//   bottom-center  theme: under Omarchy's picker
//   top-left       workspaces: next to the bar's workspace numbers, or
//                  bottom-left when the bar is at the bottom
//   tiling         bottom-right until the terminal is open, bottom-centre
//                  until the browser is, then the right edge, centred
//   right-center   layouts: clear of floating windows, which open in the
//                  middle, and of the dock along the bottom
function coachPlacement(stepId, ticked, barPosition) {
    ticked = ticked || {};
    switch (stepId) {
    case "theme": return "bottom-center";
    case "layouts": return "right-center";
    case "workspaces": return barPosition === "bottom" ? "bottom-left" : "top-left";
    case "tiling":
        if (!ticked.terminal) return "bottom-right";
        if (!ticked.browser) return "bottom-center";
        return "right-center";
    default: return "bottom-right";
    }
}

// "Super + Shift + Return" -> ["Super", "Shift", "Return"]; "Arrows" becomes
// the four arrow keys.
function keyCaps(spec) {
    if (!spec) return [];
    var out = [];
    String(spec).split("+").forEach(function (part) {
        var key = part.trim();
        if (!key) return;
        if (key === "Arrows") out.push("←", "↑", "↓", "→");
        else out.push(key);
    });
    return out;
}

var ARROWS = ["←", "↑", "↓", "→"];

// Key caps with whether a "+" goes before each: every key but the first,
// except between arrow keys, which read as one group.
function keyCapItems(spec) {
    var caps = keyCaps(spec);
    return caps.map(function (label, i) {
        var arrowRun = i > 0 && ARROWS.indexOf(label) >= 0 && ARROWS.indexOf(caps[i - 1]) >= 0;
        return { label: label, plus: i > 0 && !arrowRun };
    });
}

// The welcome checklist's rows, from what the overlay knows:
//   {online, ssid, update: "checking"|"available"|"current"|"unknown"|"updating"}
// Each row: {id, done, icon, iconFont, title, detail, action, keys, clickable}.
// `clickable`: the whole row is its button (the shortcuts row). `action`
// is the button's label, or "" for none. Icons are Nerd Font glyphs, except
// the update row's Omarchy logo, which is U+E900 in Omarchy's own "omarchy"
// font (the glyph its menu uses for Update › Omarchy).
var ICON_WIFI = "\u{F05A9}";
var ICON_WIFI_OFF = "\u{F05AA}";
var ICON_KEYBOARD = "\u{F030C}";
var ICON_OMARCHY = "\ue900";
function welcomeChecklist(status) {
    status = status || {};
    var rows = [];

    if (status.online) {
        rows.push({ id: "wifi", done: true, icon: ICON_WIFI, iconFont: "",
                    title: status.ssid ? "Connected to " + status.ssid : "Connected to the internet",
                    detail: "", action: "" });
    } else {
        rows.push({ id: "wifi", done: false, icon: ICON_WIFI_OFF, iconFont: "", title: "Not connected",
                    detail: "", action: "Connect", keys: "Super + Ctrl + W" });
    }

    // The update row only appears once online: offline there is nothing to do.
    if (status.online) {
        var update = status.update || "checking";
        var updateRow = {
            checking: { done: false, title: "Checking for updates…", detail: "", action: "" },
            current: { done: true, title: "Omarchy is up to date", detail: "", action: "" },
            available: { done: false, title: "An Omarchy update is available",
                         detail: "It takes a snapshot first, so you can roll back from the boot menu.", action: "Update" },
            updating: { done: false, title: "Updating in the terminal…", detail: "This updates by itself when it finishes.", action: "" },
            unknown: { done: false, title: "Couldn't check for updates", detail: "", action: "Try again" }
        }[update] || { done: false, title: "Updates", detail: "", action: "" };
        updateRow.id = "update";
        updateRow.icon = ICON_OMARCHY;
        updateRow.iconFont = "omarchy";
        rows.push(updateRow);
    }

    rows.push({ id: "keys", done: false, icon: ICON_KEYBOARD, iconFont: "", title: "See keyboard shortcuts",
                detail: "", action: "", clickable: true, keys: "Super + K" });
    return rows;
}

// What Omi shows on the welcome page, from the same status as the checklist:
//   {online, update: "checking"|"available"|"current"|"unknown"|"updating"}
// Offline is plain idle: the Wi-Fi row already says so.
function welcomeOmi(status) {
    status = status || {};
    if (!status.online) return "idle";
    switch (status.update || "checking") {
    case "checking": return "thinking";
    case "updating": return "updating";
    case "unknown": return "confused";
    default: return "idle";
    }
}

// The reaction, if any, when the welcome status changes from `before` to
// `after`: success when the machine comes online or an update finishes.
// Nothing for a check that just lands: that happens at every start.
function welcomeOmiReaction(before, after) {
    before = before || {};
    after = after || {};
    if (!before.online && after.online) return "success";
    if (before.update === "updating" && after.update !== "updating" && after.update !== "unknown") return "success";
    return "";
}

// What Omi shows on the other cards. Each tutorial step has a mode Omi holds
// while it's open; dialogs, the stepped-aside card, a stall and "Do it for me"
// override it. Ticks play a short success on top (Overlay.omiReact).
//   ctx: {stepId, hint, doingIt, pausing, confirm, error, away}
var STEP_OMI = {
    "super-key": "listening",
    tiling: "tiling",
    clipboard: "typing",
    theme: "excited",
    finish: "party"
};
var AWAY_OMI = { wifi: "sleeping", update: "updating", keys: "peek", menu: "peek", panel: "peek" };
function cardOmi(ctx) {
    ctx = ctx || {};
    if (ctx.error) return "error";
    // Every confirmation is for something that may ask for a password.
    if (ctx.confirm) return "sudo";
    if (ctx.pausing) return "sleeping";
    if (ctx.away) return AWAY_OMI[ctx.away] || "idle";
    if (ctx.doingIt) return "working";
    if (ctx.hint >= 2) return "confused";
    return STEP_OMI[ctx.stepId] || "idle";
}

// Where Omi looks from a card, [x, y] each -1..1 (Omi's gaze): toward what
// the step is about, from where the card sits. The pack keeps the eyes
// inside the logo, so a full look is always safe. The tiling card's mode
// has no eyes, so it has no look. After 40 s without progress (hint 1) Omi
// looks at the key caps instead: below on the Super key card, below and to
// the right of Omi on every other.
var UP_LEFT = [-1, -1];
function cardOmiLook(stepId, placement, ticked, hint) {
    ticked = ticked || {};
    if (hint === 1) return stepId === "super-key" ? [0, 1] : [1, 1];
    switch (stepId) {
    case "super-key": return [0, 1];             // the key caps below
    case "menu": return UP_LEFT;                 // the menu, mid-screen
    case "layouts": return [-1, 0];              // the windows, from the right edge
    case "window-controls": return UP_LEFT;      // the windows
    case "workspaces": return /^bottom/.test(placement) ? [0, 1] : [0, -1]; // the bar
    case "clipboard": return ticked.copy ? UP_LEFT : [0, 1]; // the line, then the terminal
    case "shortcuts": return UP_LEFT;            // the list, mid-screen
    case "theme": return [0, -1];                // the picker above the card
    default: return [0, 0];
    }
}

// The size to give an Omi item so it draws even (Meet Omi: "Drawing Omi
// crisp"): the next width up whose device pixels are a multiple of 22, so it
// is never smaller than asked, at any scale.
function evenOmiSize(px, dpr) {
    dpr = dpr || 1;
    return Math.ceil(px * dpr / 22 - 1e-6) * 22 / dpr;
}

// Where a step sits in the tutorial, for the card's eyebrow:
// "Learn the keys · 3 of 7". "" for the welcome and finish screens.
function positionLabel(manifest, stepId) {
    if (!manifest || !stepId || stepId === "welcome" || stepId === "finish") return "";
    var step = null;
    manifest.steps.forEach(function (s) { if (s.id === stepId) step = s; });
    if (!step) return "";
    var title = "";
    manifest.phases.forEach(function (p) { if (p.number === step.phase) title = p.title; });
    var siblings = manifest.steps.filter(function (s) { return s.phase === step.phase; });
    return title + " · " + (siblings.indexOf(step) + 1) + " of " + siblings.length;
}

// One display as the display step shows it. Alone, a display needs no name
// or resolution: "Built-in display, 160% scale". With more than one, each is
// told apart: "Built-in display · 3840×2160 · 160%", "DP-1 · 2560×1440 · 100%".
function monitorLine(m, count) {
    var builtIn = /^(eDP|LVDS|DSI)/i.test(m.name || "");
    var scale = Math.round(m.scale * 100) + "%";
    if (count <= 1) return (builtIn ? "Built-in display" : "Display") + ", " + scale + " scale";
    return (builtIn ? "Built-in display" : m.name) + " · " + m.width + "×" + m.height + " · " + scale;
}

function hypr(expr) {
    return ["hyprctl", "dispatch", expr];
}

function focusWindow(addr) {
    return hypr("hl.dsp.focus({ window = 'address:0x" + addr + "' })");
}

// "up" or "down" when a display's scale changed between two readings of
// `hyprctl -j monitors` scales ([number]), else "". The first display that
// changed decides.
function scaleChange(before, after) {
    if (!before || !after) return "";
    for (var i = 0; i < Math.min(before.length, after.length); i++) {
        if (after[i] > before[i]) return "up";
        if (after[i] < before[i]) return "down";
    }
    return "";
}

// Whether `hyprctl hyprsunset temperature` output means the night light is
// on: below 6000 K, as omarchy-toggle-nightlight decides. "Couldn't connect"
// (hyprsunset not running) is off.
function nightLightOn(text) {
    var m = String(text || "").match(/[0-9]+/);
    return !!m && Number(m[0]) < 6000;
}

// The night light sub-task: done once the light has changed and come back to
// how it was when the step began (on then off, or off then on), so the
// screen is left as the user had it.
//   track: {start: bool|null, changed: bool}; returns the new track and done.
function nightLightStep(track, on) {
    track = track || { start: null, changed: false };
    if (track.start === null) return { start: on, changed: false, done: false };
    var changed = track.changed || on !== track.start;
    return { start: track.start, changed: changed, done: changed && on === track.start };
}

// What "Do it for me" does for a step, given its drill's state:
//   {run: [{argv, wait}]}  commands to run in order, waiting `wait` ms after each
//   {special: "complete" | "skip"}
// It only ever acts on the drill's own windows; when it doesn't know them it
// skips rather than touch the user's other windows.
//
// ctx: {ticked: {subtask: true}, windows: {terminal, browser, active},
//       workspace: number (the focused one), home: number (where the step began),
//       layout: {start, mode} (the layouts drill's, Drills.layoutsDrill)}
function doItPlan(stepId, ctx) {
    ctx = ctx || {};
    var ticked = ctx.ticked || {};
    var w = ctx.windows || {};
    var run = function (list) { return { run: list }; };
    var step = function (argv, wait) { return { argv: argv, wait: wait || 0 }; };

    switch (stepId) {
    case "super-key":
        return { special: "complete" };
    case "theme":
        // What Super + Ctrl + Shift + Space runs: Omarchy's own theme picker.
        return run([step(["omarchy-menu", "toggle", "theme"])]);
    case "display":
        if (!ticked.up)
            return run([step(["omarchy-hyprland-monitor-scaling", "up"], 1800), step(["omarchy-hyprland-monitor-scaling", "down"])]);
        if (!ticked.down) return run([step(["omarchy-hyprland-monitor-scaling", "down"])]);
        return run([step(["omarchy-toggle-nightlight"], 2500), step(["omarchy-toggle-nightlight"])]);
    case "clipboard":
        // Copy the line, then paste it into the terminal as Super + V would
        // there: Ctrl + Shift + V to the focused surface.
        if (!ticked.copy) return run([step(["wl-copy", CLIPBOARD_SAMPLE])]);
        var key = function (state) {
            return hypr("hl.dsp.send_key_state({ mods = 'CTRL SHIFT', key = 'V', state = '" + state + "' })");
        };
        return run([step(hypr("hl.dsp.focus({ window = 'class:^" + SAMPLE_APP_ID + "$' })"), 400),
                    step(key("down"), 60), step(key("up"))]);
    case "menu":
        if (!ticked.open) return run([step(["omarchy-menu", "toggle"], 1500), step(["omarchy-menu", "toggle"])]);
        return run([step(["omarchy-menu", "toggle"])]);
    case "shortcuts":
        // The list is the menu's layer, so the menu's toggle closes it.
        if (!ticked.open) return run([step(["omarchy-menu-keybindings"], 2000), step(["omarchy-menu", "toggle"])]);
        return run([step(["omarchy-menu", "toggle"])]);
    case "layouts":
        return layoutsPlan(ticked, w, Number(ctx.home) || 1, ctx.layout || {});
    case "tiling":
        if (!ticked.terminal) return run([step(["omarchy-launch-terminal"])]);
        if (!ticked.browser) return run([step(["omarchy-launch-browser"])]);
        if (!w.terminal || !w.browser) return { special: "skip" };
        if (!ticked.split) return run([step(focusWindow(w.terminal), 300), step(hypr('hl.dsp.layout("togglesplit")'))]);
        return run([step(focusWindow(w.active === w.terminal ? w.browser : w.terminal))]);
    case "window-controls":
        // Float and full screen on the terminal; close the browser last.
        if (!ticked.float || !ticked.fullscreen) {
            if (!w.terminal) return { special: "skip" };
            var action = !ticked.float ? "hl.dsp.window.float({ action = 'toggle' })"
                                       : "hl.dsp.window.fullscreen({ mode = 'fullscreen' })";
            return run([step(focusWindow(w.terminal), 300), step(hypr(action), 700), step(hypr(action))]);
        }
        if (!w.browser) return { special: "skip" };
        return run([step(hypr("hl.dsp.window.close({ window = 'address:0x" + w.browser + "' })"))]);
    case "workspaces":
        // Each monitor has its own workspaces 1-10, numbered 11-20 on the
        // second and so on, so the neighbour stays within the block.
        var here = Number(ctx.home) || Number(ctx.workspace) || 1;
        var there = (here - 1) % 10 >= 8 ? here - 1 : here + 1;
        if (!ticked.switch)
            return run([step(hypr("hl.dsp.focus({ workspace = '" + there + "' })"), 900),
                        step(hypr("hl.dsp.focus({ workspace = '" + here + "' })"))]);
        if (!ticked.back) return run([step(hypr("hl.dsp.focus({ workspace = '" + here + "' })"))]);
        if (!w.terminal) return { special: "skip" };
        return run([step(focusWindow(w.terminal), 300), step(hypr("hl.dsp.window.move({ workspace = '" + there + "' })"))]);
    default:
        return null;
    }
}

// The order Super + L cycles a workspace's layout through
// (omarchy-hyprland-workspace-layout-toggle).
var LAYOUTS = ["dwindle", "scrolling", "floating"];

// The layouts step's "Do it for me": what Super + L, Super + M and a click in
// the dock do, on the workspace the step began on. `layout` is where it began
// and where it is now; unknown counts as tiling, the default.
function layoutsPlan(ticked, w, home, layout) {
    var mode = layout.mode || "dwindle";
    var step = function (argv, wait) { return { argv: argv, wait: wait || 0 }; };
    // Super + L until the workspace is in `to`, from wherever it is.
    var cycleTo = function (to) {
        var presses = (LAYOUTS.indexOf(to) - LAYOUTS.indexOf(mode) + LAYOUTS.length) % LAYOUTS.length;
        var out = [step(hypr("hl.dsp.focus({ workspace = '" + home + "' })"), 300)];
        for (var i = 0; i < presses; i++) out.push(step(["omarchy-hyprland-workspace-layout-toggle"], 1200));
        return out;
    };
    if (!ticked.scrolling) return { run: cycleTo("scrolling") };
    if (!ticked.floating) return { run: cycleTo("floating") };
    if (!ticked.minimize) {
        if (!w.terminal) return { special: "skip" };
        return { run: cycleTo("floating").concat([
            step(["omarchy-hyprland-window-minimize", "0x" + w.terminal], 1500),
            step(hypr("hl.dsp.window.move({ workspace = '" + home + "', window = 'address:0x" + w.terminal + "' })"), 300),
            step(focusWindow(w.terminal))]) };
    }
    return { run: cycleTo(layout.start || "dwindle") };
}
