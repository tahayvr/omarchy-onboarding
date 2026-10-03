.pragma library

// Pure helpers for the overlay's view: key caps, idle hints and what
// "Do it for me" runs. Kept out of QML so node can test them.

// Spec edge case: after 20 s without progress the key-cap hint grows; after
// 40 s the overlay offers "Do it for me".
var HINT_AFTER_MS = 20000;
var DO_IT_AFTER_MS = 40000;

// The line step 8 prints in a terminal for the user to copy and paste.
var CLIPBOARD_SAMPLE = "Omarchy copies and pastes the same way everywhere";

// Steps shown as a centered card that takes the keyboard. Every other step
// is a small card in the corner that leaves the keyboard to Hyprland, so
// Super shortcuts and the panels they open always reach it.
var CENTERED_STEPS = ["welcome", "super-key", "finish"];

// When a step finishes by itself, the card stays this long so Omi's success
// (1.2 s, CardOmi) plays on it, with every sub-task ticked, before the next.
var CELEBRATE_MS = 1500;

// 0: plain, 1: bigger key caps, 2: also offer "Do it for me".
function hintLevel(idleMs) {
    if (idleMs >= DO_IT_AFTER_MS) return 2;
    if (idleMs >= HINT_AFTER_MS) return 1;
    return 0;
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
function coachPlacement(stepId, ticked, barPosition) {
    ticked = ticked || {};
    switch (stepId) {
    case "theme": return "bottom-center";
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
// Each row: {id, done, icon, iconFont, title, detail, action, keys}. `action`
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

    rows.push({ id: "keys", done: false, info: true, icon: ICON_KEYBOARD, iconFont: "", title: "See keyboard shortcuts",
                detail: "", action: "Show all", keys: "Super + K" });
    return rows;
}

// What Omi shows on the welcome page, from the same status as the checklist.
// Modes are the Omi pack's, used as docs/omarchy.md in Meet Omi suggests.
function welcomeOmi(status) {
    status = status || {};
    if (!status.online) return "offline-searching";
    switch (status.update || "checking") {
    case "checking": return "thinking";
    case "updating": return "updating";
    case "unknown": return "confused";
    default: return "idle";
    }
}

// The reaction, if any, when Omi's welcome mode changes from `before` to
// `after`: success when the machine comes online or an update finishes.
// Nothing for a check that just lands: that happens at every start.
function welcomeOmiReaction(before, after) {
    if (before === after) return "";
    if (before === "offline-searching" || before === "updating") return after === "idle" || after === "thinking" ? "success" : "";
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
var AWAY_OMI = { wifi: "offline-searching", update: "updating", keys: "peek" };
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

// What "Do it for me" does for a step, given its drill's state:
//   {run: [{argv, wait}]}  commands to run in order, waiting `wait` ms after each
//   {special: "complete" | "fill" | "skip"}
// It only ever acts on the drill's own windows; when it doesn't know them it
// skips rather than touch the user's other windows.
//
// ctx: {ticked: {subtask: true}, windows: {terminal, browser, active},
//       workspace: number (the focused one), home: number (where the step began)}
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
        return { special: "fill" };
    case "menu":
        if (!ticked.open) return run([step(["omarchy-menu", "toggle"], 1500), step(["omarchy-menu", "toggle"])]);
        return run([step(["omarchy-menu", "toggle"])]);
    case "shortcuts":
        // The list is the menu's layer, so the menu's toggle closes it.
        if (!ticked.open) return run([step(["omarchy-menu-keybindings"], 2000), step(["omarchy-menu", "toggle"])]);
        return run([step(["omarchy-menu", "toggle"])]);
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
        var here = Number(ctx.home) || Number(ctx.workspace) || 1;
        var there = here >= 9 ? here - 1 : here + 1;
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
