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
// Super shortcuts always reach it.
// Steps that open a shell panel (network, audio, Bluetooth) or teach keys
// stay in the corner too, so the panel or Hyprland gets the keyboard.
var CENTERED_STEPS = ["welcome", "personal-setup", "super-key", "theme", "ai-agent", "dev-basics", "finish"];

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

// The welcome screen's track choice: three buttons, the middle one asking
// "Mac or Windows?" before it picks.
var TRACK_CHOICES = [
    { id: "new-to-linux", label: "New to Linux", detail: "Start from the basics." },
    { id: "switcher", label: "Coming from Mac or Windows", detail: "Learn where your habits land." },
    { id: "knows-linux", label: "I know Linux", detail: "Just show me Omarchy." }
];

// The hardware check's items, from detection. facts: {bluetooth, fingerprint,
// missing}. Each item: {id, title, detail, action, confirm, requires}.
//   action   what its button does: "panel:<id>", "sound", or "run:<argv>"
//   confirm  the question asked first when it changes the system
function hardwareItems(facts) {
    facts = facts || {};
    var missing = facts.missing || [];
    var items = [
        { id: "audio", title: "Sound", detail: "Play a test sound on the left and right speakers.",
          action: "sound", requires: "pw-play" },
        { id: "bluetooth", title: "Bluetooth", detail: "Pair headphones, a mouse or a keyboard.",
          action: "panel:omarchy.bluetooth", keys: "Super + Ctrl + B", requires: "bluetoothctl", when: facts.bluetooth },
        { id: "fingerprint", title: "Fingerprint", detail: "Unlock and sudo with your finger.",
          action: "run:omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-fingerprint",
          confirm: "Set up the fingerprint reader? This installs fprintd and changes how you log in.",
          requires: "omarchy setup security fingerprint", when: facts.fingerprint },
        { id: "firmware", title: "Firmware", detail: "Check for firmware updates for this machine.",
          action: "run:omarchy-launch-floating-terminal-with-presentation omarchy-update-firmware",
          confirm: "Check for firmware updates? This installs fwupd if needed and may ask to flash updates.",
          requires: "omarchy update firmware" }
    ];
    return items.filter(function (item) {
        return item.when !== false && missing.indexOf(item.requires) < 0;
    });
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
    case "internet":
        return run([step(["omarchy-shell", "shell", "toggle", "omarchy.network"])]);
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
