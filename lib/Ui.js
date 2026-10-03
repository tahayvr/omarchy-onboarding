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
var CENTERED_STEPS = ["welcome", "super-key", "theme", "finish"];

// 0: plain, 1: bigger key caps, 2: also offer "Do it for me".
function hintLevel(idleMs) {
    if (idleMs >= DO_IT_AFTER_MS) return 2;
    if (idleMs >= HINT_AFTER_MS) return 1;
    return 0;
}

function isCentered(stepId) {
    return CENTERED_STEPS.indexOf(stepId) >= 0;
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
//   {online, ssid, update: "offline"|"checking"|"available"|"current"|"unknown"|"updating"}
// Each row: {id, done, title, detail, action, keys}. `action` is the button's
// label, or "" for none.
function welcomeChecklist(status) {
    status = status || {};
    var rows = [];

    if (status.online) {
        rows.push({ id: "wifi", done: true, title: status.ssid ? "Connected to " + status.ssid : "Connected to the internet",
                    detail: "", action: "" });
    } else {
        rows.push({ id: "wifi", done: false, title: "Not connected",
                    detail: "Open the network panel and pick your Wi-Fi, or press Super + Ctrl + W any time.",
                    action: "Connect", keys: "Super + Ctrl + W" });
    }

    var update = status.online ? (status.update || "checking") : "offline";
    var updateRow = {
        offline: { done: false, title: "Updates", detail: "Connect to the internet to check for updates.", action: "" },
        checking: { done: false, title: "Checking for updates…", detail: "", action: "" },
        current: { done: true, title: "Omarchy is up to date", detail: "", action: "" },
        available: { done: false, title: "An Omarchy update is available",
                     detail: "It takes a snapshot first, so you can roll back from the boot menu.", action: "Update" },
        updating: { done: false, title: "Updating in the terminal…", detail: "This updates by itself when it finishes.", action: "" },
        unknown: { done: false, title: "Couldn't check for updates", detail: "", action: "Try again" }
    }[update] || { done: false, title: "Updates", detail: "", action: "" };
    updateRow.id = "update";
    rows.push(updateRow);

    rows.push({ id: "keys", done: false, info: true, title: "Every shortcut, one key away",
                detail: "No need to memorize anything.", action: "Show all", keys: "Super + K" });
    return rows;
}

function hypr(expr) {
    return ["hyprctl", "dispatch", expr];
}

function focusWindow(addr) {
    return hypr("hl.dsp.focus({ window = 'address:0x" + addr + "' })");
}

// What "Do it for me" does for a step, given its drill's state:
//   {run: [{argv, wait}]}  commands to run in order, waiting `wait` ms after each
//   {special: "complete" | "fill" | "skip"}
// It only ever acts on the drill's own windows; when it doesn't know them it
// skips rather than touch the user's other windows.
//
// ctx: {ticked: {subtask: true}, windows: {terminal, browser, active}, workspace: number}
function doItPlan(stepId, ctx) {
    ctx = ctx || {};
    var ticked = ctx.ticked || {};
    var w = ctx.windows || {};
    var run = function (list) { return { run: list }; };
    var step = function (argv, wait) { return { argv: argv, wait: wait || 0 }; };

    switch (stepId) {
    case "super-key":
        return { special: "complete" };
    case "display":
        if (!ticked.scale)
            return run([step(["omarchy-hyprland-monitor-scaling", "up"], 1800), step(["omarchy-hyprland-monitor-scaling", "down"])]);
        return run([step(["omarchy-toggle-nightlight"], 2500), step(["omarchy-toggle-nightlight"])]);
    case "clipboard":
        return { special: "fill" };
    case "menu":
        if (!ticked.open) return run([step(["omarchy-menu", "toggle"], 1500), step(["omarchy-menu", "toggle"])]);
        return run([step(["omarchy-menu", "toggle"])]);
    case "shortcuts":
        return run([step(["omarchy-menu-keybindings"])]);
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
        var here = Number(ctx.workspace) || 1;
        var there = here >= 9 ? here - 1 : here + 1;
        if (!ticked.switch)
            return run([step(hypr("hl.dsp.focus({ workspace = '" + there + "' })"), 900),
                        step(hypr("hl.dsp.focus({ workspace = '" + here + "' })"))]);
        if (!w.terminal) return { special: "skip" };
        return run([step(focusWindow(w.terminal), 300), step(hypr("hl.dsp.window.move({ workspace = '" + there + "' })"))]);
    default:
        return null;
    }
}
