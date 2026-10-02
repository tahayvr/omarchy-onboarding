.pragma library

// Trackers for the "Learn to move" drills (steps 4–7 and 9). Each turns
// observations into sub-task ticks. Sub-task ids match steps.json.
//
// An observation is one of:
//   {kind: "hypr", line: "name>>data"}   a Hyprland event, as socket2 prints it
//   {kind: "keybindings", open: bool}     sent right before each
//                                         openlayer>>omarchy-menu: whether that
//                                         layer is the Super + K list
//   {kind: "clients", windows: [...]}     window positions, when they change
// Recordings (tests/fixtures/*.jsonl) are these objects one per line, with a
// `t` in milliseconds.

var MENU_LAYER = "omarchy-menu";
var DRILL_STEPS = ["menu", "tiling", "window-controls", "workspaces", "shortcuts"];

// Browser window classes for the browsers Omarchy offers as a default.
var BROWSER_CLASSES = ["chromium", "google-chrome", "brave-browser", "firefox", "zen", "librewolf",
                       "vivaldi-stable", "microsoft-edge"];

// ---------------------------------------------------------------- events

// Parses one Hyprland event line into {name, ...fields}, or null for events
// the drills don't use. Formats are from Hyprland 0.56.2 (see FINDINGS.md).
function parseEvent(line) {
    var text = String(line || "").replace(/[\r\n]+$/, "");
    var at = text.indexOf(">>");
    if (at < 0) return null;
    var name = text.slice(0, at), data = text.slice(at + 2);
    var parts;
    switch (name) {
    case "openwindow":
        // ADDR,WORKSPACE_NAME,CLASS,TITLE — the title may contain commas.
        parts = data.split(",");
        if (parts.length < 3) return null;
        return { name: name, addr: parts[0], workspace: parts[1], cls: parts[2], title: parts.slice(3).join(",") };
    case "closewindow":
        return { name: name, addr: data };
    case "activewindowv2":
        return { name: name, addr: data && data !== "," ? data : null };
    case "workspacev2":
        parts = data.split(",");
        return parts.length < 2 ? null : { name: name, id: parts[0], workspace: parts.slice(1).join(",") };
    case "movewindowv2":
        parts = data.split(",");
        return parts.length < 3 ? null : { name: name, addr: parts[0], workspace: parts.slice(2).join(",") };
    case "changefloatingmode":
        parts = data.split(",");
        return parts.length < 2 ? null : { name: name, addr: parts[0], floating: parts[1] === "1" };
    case "fullscreen":
        // No address: it is the active window.
        return { name: name, on: data === "1" };
    case "openlayer":
    case "closelayer":
        return { name: name, namespace: data };
    default:
        return null;
    }
}

// Hyprland prints `0x62d9…` in JSON and `62d9…` in events. Use the event form.
function normalizeAddr(addr) {
    return String(addr || "").replace(/^0x/, "");
}

// ---------------------------------------------------------------- classes

// Mirrors Omarchy's terminal tag rule in default/hypr/apps/terminals.lua.
function isTerminal(cls) {
    return ["Alacritty", "kitty", "com.mitchellh.ghostty", "foot", "org.codeberg.dnkl.foot", "wezterm"].indexOf(cls) >= 0
        || cls.indexOf("org.omarchy.") === 0 || cls.indexOf("TUI.") === 0;
}

// defaultBrowser is `omarchy default browser`, e.g. "chromium".
function isBrowser(cls, defaultBrowser) {
    var c = String(cls || "").toLowerCase();
    if (BROWSER_CLASSES.indexOf(c) >= 0) return true;
    return !!defaultBrowser && String(defaultBrowser).replace(/\.desktop$/, "").toLowerCase() === c;
}

// ---------------------------------------------------------------- drills

// A tracker has: step, subtasks, ticked (id -> true), observe(obs) returning
// [{subtask, ticked}] changes, and complete().
function create(step, options) {
    var make = { "menu": menuDrill, "tiling": tilingDrill, "window-controls": windowControlsDrill,
                 "workspaces": workspacesDrill, "shortcuts": shortcutsDrill }[step];
    return make ? make(options || {}) : null;
}

function base(step, subtasks) {
    var d = { step: step, subtasks: subtasks, ticked: {} };
    d.tick = function (id, out) {
        if (!d.ticked[id]) { d.ticked[id] = true; out.push({ subtask: id, ticked: true }); }
    };
    d.untick = function (id, out) {
        if (d.ticked[id]) { delete d.ticked[id]; out.push({ subtask: id, ticked: false }); }
    };
    d.complete = function () {
        return d.subtasks.every(function (id) { return d.ticked[id]; });
    };
    return d;
}

function eventOf(obs) {
    return obs && obs.kind === "hypr" ? parseEvent(obs.line) : null;
}

// Step 4: open the menu with Super + Space, then close it.
function menuDrill() {
    var d = base("menu", ["open", "close"]);
    var nextIsKeybindings = false, open = false;
    d.observe = function (obs) {
        var out = [];
        if (obs.kind === "keybindings") nextIsKeybindings = !!obs.open;
        var e = eventOf(obs);
        if (!e) return out;
        if (e.name === "openlayer" && e.namespace === MENU_LAYER) {
            // The keybindings list uses the same layer; it doesn't count here.
            var keybindings = nextIsKeybindings;
            nextIsKeybindings = false;
            if (!keybindings) {
                open = true;
                d.tick("open", out);
            }
        } else if (e.name === "closelayer" && e.namespace === MENU_LAYER && open) {
            open = false;
            d.tick("close", out);
        }
        return out;
    };
    return d;
}

// Step 9: open the keybindings list with Super + K.
function shortcutsDrill() {
    var d = base("shortcuts", ["open"]);
    var nextIsKeybindings = false;
    d.observe = function (obs) {
        var out = [];
        if (obs.kind === "keybindings") nextIsKeybindings = !!obs.open;
        var e = eventOf(obs);
        if (e && e.name === "openlayer" && e.namespace === MENU_LAYER) {
            if (nextIsKeybindings) d.tick("open", out);
            nextIsKeybindings = false;
        }
        return out;
    };
    return d;
}

// Step 5: open a terminal and a browser, toggle the split, move focus.
// Super + J sends no event, so the split is seen through window positions.
function tilingDrill(options) {
    var d = base("tiling", ["terminal", "browser", "split", "focus"]);
    var terminal = null, browser = null, active = null, justOpened = null, split = null;

    function sameWorkspace() {
        return !!(terminal && browser && terminal.workspace === browser.workspace);
    }
    function isPairMember(addr) {
        return !!(terminal && browser && (terminal.addr === addr || browser.addr === addr));
    }
    function observeClients(windows, out) {
        if (!sameWorkspace()) return;
        var t = null, b = null;
        windows.forEach(function (w) {
            if (w.addr === terminal.addr) t = w;
            if (w.addr === browser.addr) b = w;
        });
        if (!t || !b) return;
        var dx = (t.x * 2 + t.width) - (b.x * 2 + b.width);
        var dy = (t.y * 2 + t.height) - (b.y * 2 + b.height);
        var now = Math.abs(dx) >= Math.abs(dy) ? "side-by-side" : "stacked";
        if (split && split !== now) d.tick("split", out);
        split = now;
    }

    d.complete = function () {
        return d.subtasks.every(function (id) { return d.ticked[id]; }) && sameWorkspace();
    };

    d.observe = function (obs) {
        var out = [];
        if (obs.kind === "clients") {
            observeClients(obs.windows || [], out);
            return out;
        }
        var e = eventOf(obs);
        if (!e) return out;
        if (e.name === "openwindow") {
            var w = { addr: e.addr, workspace: e.workspace };
            if (!terminal && isTerminal(e.cls)) {
                terminal = w;
                d.tick("terminal", out);
            } else if (!browser && isBrowser(e.cls, options.defaultBrowser)) {
                browser = w;
                d.tick("browser", out);
            } else {
                return out;
            }
            // Hyprland focuses a window as it opens; that isn't the user moving focus.
            justOpened = e.addr;
            split = null;
        } else if (e.name === "closewindow") {
            // Closing a drill window resets only its own sub-task.
            if (terminal && terminal.addr === e.addr) {
                terminal = null;
                d.untick("terminal", out);
            } else if (browser && browser.addr === e.addr) {
                browser = null;
                d.untick("browser", out);
            }
            split = null;
        } else if (e.name === "movewindowv2") {
            [terminal, browser].forEach(function (win) {
                if (win && win.addr === e.addr) win.workspace = e.workspace;
            });
            split = null;
        } else if (e.name === "activewindowv2" && e.addr) {
            if (justOpened === e.addr) {
                justOpened = null;
            } else if (isPairMember(e.addr) && active && active !== e.addr && isPairMember(active)) {
                d.tick("focus", out);
            }
            active = e.addr;
        }
        return out;
    };
    return d;
}

// Step 6: float and tile again, full screen and back, close a window.
function windowControlsDrill() {
    var d = base("window-controls", ["float", "fullscreen", "close"]);
    var floated = {}, fullscreen = false;
    d.observe = function (obs) {
        var out = [];
        var e = eventOf(obs);
        if (!e) return out;
        if (e.name === "changefloatingmode") {
            if (e.floating) floated[e.addr] = true;
            else if (floated[e.addr]) {
                delete floated[e.addr];
                d.tick("float", out);
            }
        } else if (e.name === "fullscreen") {
            if (e.on) fullscreen = true;
            else if (fullscreen) {
                fullscreen = false;
                d.tick("fullscreen", out);
            }
        } else if (e.name === "closewindow") {
            d.tick("close", out);
        }
        return out;
    };
    return d;
}

// Step 7: switch workspaces and send a window to another one.
function workspacesDrill() {
    var d = base("workspaces", ["switch", "move"]);
    d.observe = function (obs) {
        var out = [];
        var e = eventOf(obs);
        if (e && e.name === "workspacev2") d.tick("switch", out);
        if (e && e.name === "movewindowv2") d.tick("move", out);
        return out;
    };
    return d;
}

// ---------------------------------------------------------------- probes

// `nmcli networking connectivity`: full is online; none, limited and portal
// are not; anything else is unknown (null).
function parseConnectivity(text) {
    var s = String(text || "").trim();
    if (s === "full") return true;
    if (s === "none" || s === "limited" || s === "portal") return false;
    return null;
}

// `hyprctl -j clients` -> [{addr, workspace, x, y, width, height}], mapped only.
function parseClients(json) {
    var raw;
    try {
        raw = JSON.parse(json);
    } catch (e) {
        return null;
    }
    if (!Array.isArray(raw)) return null;
    return raw.filter(function (c) { return c.mapped !== false; }).map(function (c) {
        return {
            addr: normalizeAddr(c.address),
            workspace: String(c.workspace && c.workspace.name),
            x: c.at[0], y: c.at[1], width: c.size[0], height: c.size[1]
        };
    });
}

// Whether two client lists differ, so positions are only sent on change.
function sameClients(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
}

// ---------------------------------------------------------------- walker

// Runs the drills in flow order, from `from` (a drill step id, default the
// first), moving on as each completes. feed(obs) returns what happened:
// [{type: "tick", step, subtask, ticked}] and {type: "complete", step};
// after the last drill, done() is true.
function walker(options, from) {
    var start = from ? DRILL_STEPS.indexOf(from) : 0;
    if (start < 0) throw new Error("'" + from + "' is not a drill (expected one of: " + DRILL_STEPS.join(", ") + ")");
    var w = { index: start, drill: create(DRILL_STEPS[start], options) };
    w.done = function () { return w.drill === null; };
    w.feed = function (obs) {
        var out = [];
        if (!w.drill) return out;
        w.drill.observe(obs).forEach(function (c) {
            out.push({ type: "tick", step: w.drill.step, subtask: c.subtask, ticked: c.ticked });
        });
        if (w.drill.complete()) {
            out.push({ type: "complete", step: w.drill.step });
            w.index++;
            w.drill = w.index < DRILL_STEPS.length ? create(DRILL_STEPS[w.index], options) : null;
        }
        return out;
    };
    return w;
}
