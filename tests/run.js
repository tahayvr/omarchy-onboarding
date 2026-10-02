#!/usr/bin/env node
// Unit tests for lib/Engine.js and lib/Drills.js. Run with `node tests/run.js`.
// The libraries are QML `.pragma library` files, so they are evaluated in a
// bare VM context rather than required as modules.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.join(__dirname, "..");

function lib(name) {
    const file = path.join(ROOT, "lib", name);
    const src = fs.readFileSync(file, "utf8").replace(/^\.pragma library\s*/, "");
    const ctx = vm.createContext({ Math, JSON, Object, Array, String, Number, RegExp, Error });
    vm.runInContext(src, ctx, { filename: file });
    return ctx;
}

const E = lib("Engine.js");
const D = lib("Drills.js");
const U = lib("Ui.js");
const MANIFEST = JSON.parse(fs.readFileSync(path.join(ROOT, "steps.json"), "utf8"));

let passed = 0, failed = 0;
function test(name, fn) {
    try { fn(); passed++; }
    catch (e) { failed++; console.log("FAIL  " + name + "\n      " + String(e.stack || e).split("\n").slice(0, 3).join("\n      ")); }
}
function eq(actual, expected, what) {
    if (JSON.stringify(actual) !== JSON.stringify(expected))
        throw new Error((what || "value") + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
}
function ok(cond, what) { if (!cond) throw new Error(what || "expected truthy"); }
function throws(fn, fragment) {
    try { fn(); } catch (e) {
        if (!String(e.message).includes(fragment)) throw new Error("error '" + e.message + "' lacks '" + fragment + "'");
        return;
    }
    throw new Error("expected an error containing '" + fragment + "'");
}
function copy(x) { return JSON.parse(JSON.stringify(x)); }

// ================================================================ manifest

const NOW = 1000;
const ONLINE = { online: true, owner_setup_deferred: false };
const OFFLINE = { online: false, owner_setup_deferred: false };

const MINIMAL = {
    phases: [{ number: 0, title: "Start" }],
    steps: [
        { id: "welcome", number: 0, phase: 0, title: "Welcome", done_when: "a track is picked" },
        { id: "finish", number: 1, phase: 0, title: "Done", done_when: "Finish pressed" }
    ]
};

test("the real manifest is valid and matches the spec", () => {
    E.validateManifest(MANIFEST);
    eq(MANIFEST.steps.length, 18, "steps");
    eq(MANIFEST.phases.length, 7, "phases");
    eq(MANIFEST.steps.filter(s => s.core).length, 10, "core steps");
});

test("a minimal manifest is valid", () => { E.validateManifest(copy(MINIMAL)); });

test("unknown keys are rejected", () => {
    const m = copy(MINIMAL); m.steps[1].skip_iff = [];
    throws(() => E.validateManifest(m), "unknown key 'skip_iff'");
});

test("unknown facts and tracks are rejected", () => {
    let m = copy(MINIMAL); m.steps.splice(1, 0, { id: "x", number: 1, phase: 0, title: "X", done_when: "y", skip_if: ["onlin"] });
    m.steps[2].number = 2;
    throws(() => E.validateManifest(m), "unknown fact 'onlin'");
    m = copy(MINIMAL); m.steps.splice(1, 0, { id: "x", number: 1, phase: 0, title: "X", done_when: "y", tip: "t", hide_tracks: ["linux"] });
    m.steps[2].number = 2;
    throws(() => E.validateManifest(m), "unknown track 'linux'");
});

test("welcome must come first and finish last", () => {
    const m = copy(MINIMAL); m.steps[0].id = "hello";
    throws(() => E.validateManifest(m), "first step must be 'welcome'");
});

test("step numbers must be sequential", () => {
    const m = copy(MINIMAL); m.steps[1].number = 5;
    throws(() => E.validateManifest(m), "expected 1");
});

test("finish cannot have skip rules", () => {
    const m = copy(MINIMAL); m.steps[1].skip_if = ["online"];
    throws(() => E.validateManifest(m), "cannot have skip rules");
});

test("hiding a step on a track needs a tip", () => {
    const m = copy(MINIMAL);
    m.steps.splice(1, 0, { id: "x", number: 1, phase: 0, title: "X", done_when: "y", hide_tracks: ["mac"] });
    m.steps[2].number = 2;
    throws(() => E.validateManifest(m), "has no tip");
});

// ================================================================ state

test("empty state text is a fresh state", () => {
    eq(E.parseState("", 5).status, "not-started");
    eq(E.parseState("  \n", 5).created_at, 5);
});

test("state round-trips through text", () => {
    const s = E.start(MANIFEST, E.newState(1), ONLINE, 2);
    eq(E.parseState(E.serialize(s), 3), s);
});

test("corrupt or newer state is refused", () => {
    throws(() => E.parseState("{ nope", 1), "state file is corrupt");
    throws(() => E.parseState(JSON.stringify({ version: 99 }), 1), "has version 99");
});

test("older state gains missing keys", () => {
    const s = E.parseState(JSON.stringify({ version: 1, status: "paused", steps: {} }), 7);
    eq(s.mode, "full");
    eq(s.pause_notified, false);
});

// ================================================================ lifecycle


// A small driver over the pure functions, like the overlay uses them.
function run(facts) {
    const r = { m: MANIFEST, s: E.newState(NOW), facts: facts || ONLINE };
    r.current = () => { const st = E.currentStep(r.m, r.s); return st ? st.id : null; };
    r.start = () => { r.s = E.start(r.m, r.s, r.facts, NOW); return r; };
    r.track = (t, code) => { r.s = E.chooseTrack(r.s, t, code, NOW); return r; };
    r.done = () => { r.s = E.complete(r.m, r.s, r.facts, NOW); return r; };
    r.skip = () => { r.s = E.skip(r.m, r.s, r.facts, NOW); return r; };
    r.walk = () => {
        const shown = [];
        while (r.s.status === "in-progress") { shown.push(r.current()); r.done(); }
        return shown;
    };
    return r;
}

function started(facts, track, code) {
    return run(facts).start().track(track || "new-to-linux", !!code).done();
}

// Not started

test("not started autostarts at login", () => {
    const r = run();
    eq(E.login(r.s, NOW).action, "start");
    eq(r.current(), null);
});

test("starting opens the welcome step", () => {
    const r = run().start();
    eq(r.s.status, "in-progress");
    eq(r.current(), "welcome");
});

test("welcome needs a track", () => {
    const r = run().start();
    throws(() => r.done(), "pick a track");
    throws(() => r.skip(), "pick a track");
    r.track("mac", true).done();
    eq(r.s.track, "mac");
    eq(r.s.writes_code, true);
});

test("the track can only be picked on welcome", () => {
    const r = started(ONLINE, "mac");
    throws(() => r.track("windows"), "only be picked on the welcome step");
});

test("unknown tracks are rejected", () => {
    throws(() => run().start().track("linux"), "unknown track 'linux'");
});

// In progress

test("in progress resumes at the current step after a reboot", () => {
    const r = started(ONLINE).done(); // super-key
    eq(r.current(), "menu");
    const saved = E.parseState(E.serialize(r.s), NOW);
    eq(E.login(saved, NOW), { action: "resume", step: "menu", state: saved });
    eq(E.currentStep(MANIFEST, E.start(MANIFEST, saved, ONLINE, NOW)).id, "menu");
});

test("resume re-checks the current step", () => {
    const r = started(OFFLINE);
    eq(r.current(), "internet");
    const back = E.start(MANIFEST, r.s, ONLINE, NOW);
    eq(E.currentStep(MANIFEST, back).id, "super-key");
    eq(back.steps.internet.outcome, "auto-skipped");
});

test("functions never mutate their input", () => {
    const r = started(ONLINE);
    const before = copy(r.s);
    E.complete(MANIFEST, r.s, ONLINE, NOW);
    E.pause(r.s, NOW);
    E.login(r.s, NOW);
    eq(r.s, before);
});

// Paused

test("paused reminds once, then stays quiet", () => {
    const r = started(ONLINE);
    r.s = E.pause(r.s, NOW);
    eq(r.s.status, "paused");
    eq(r.current(), null);
    let l = E.login(r.s, NOW);
    eq(l.action, "remind");
    eq(E.login(l.state, NOW).action, "nothing");
});

test("paused resumes where it stopped and earns a new reminder", () => {
    const r = started(ONLINE);
    const step = r.current();
    r.s = E.login(E.pause(r.s, NOW), NOW).state;
    r.start();
    eq(r.current(), step);
    eq(E.login(E.pause(r.s, NOW), NOW).action, "remind");
});

test("steps cannot change while paused", () => {
    const r = started(ONLINE);
    r.s = E.pause(r.s, NOW);
    throws(() => r.done(), "while onboarding is paused");
    throws(() => E.pause(r.s, NOW), "while onboarding is paused");
});

// Completed

test("finishing completes and never autostarts again", () => {
    const r = started(ONLINE, "new-to-linux", true);
    const shown = r.walk();
    eq(shown[shown.length - 1], "finish");
    eq(r.s.status, "completed");
    eq(r.s.current, null);
    eq(E.login(r.s, NOW).action, "nothing");
    throws(() => r.start(), "while onboarding is completed");
});

test("every step is skippable", () => {
    const r = started(OFFLINE, "new-to-linux", true);
    while (r.s.status === "in-progress") r.skip();
    eq(r.s.status, "completed");
});

// Dismissed

test("dismiss is reachable from every step", () => {
    const reference = started(OFFLINE, "new-to-linux", true).walk();
    reference.forEach((expected, stopAt) => {
        const r = started(OFFLINE, "new-to-linux", true);
        for (let i = 0; i < stopAt; i++) r.done();
        eq(r.current(), expected);
        r.s = E.dismiss(r.s, NOW);
        eq(r.s.status, "dismissed");
        eq(E.login(r.s, NOW).action, "nothing");
    });
});

test("dismiss works before starting and while paused, not after completing", () => {
    eq(E.dismiss(E.newState(NOW), NOW).status, "dismissed");
    const r = started(ONLINE, "mac");
    eq(E.dismiss(E.pause(r.s, NOW), NOW).status, "dismissed");
    r.walk();
    throws(() => E.dismiss(r.s, NOW), "while onboarding is completed");
});

// Track and skip rules

test("online machines skip the internet step", () => {
    const r = started(ONLINE);
    eq(r.current(), "super-key");
    eq(r.s.steps.internet.outcome, "auto-skipped");
    eq(r.s.steps.internet.reason, "already online");
});

test("unknown connectivity shows the internet step", () => {
    eq(started({ online: null, owner_setup_deferred: false }).current(), "internet");
});

test("personal setup only after an install for another owner", () => {
    eq(started(ONLINE).s.steps["personal-setup"].outcome, "auto-skipped");
    eq(started({ online: true, owner_setup_deferred: true }).current(), "personal-setup");
    // Unknown means "not deferred": the step is rare and needs proof.
    eq(started({ online: true, owner_setup_deferred: null }).s.steps["personal-setup"].outcome, "auto-skipped");
});

test("the knows-linux track gets tips instead of basic drills", () => {
    const r = started(ONLINE, "knows-linux");
    const shown = r.walk();
    ok(!shown.includes("window-controls") && !shown.includes("clipboard"), shown.join(","));
    eq(r.s.steps.clipboard, { outcome: "auto-skipped", at: NOW, reason: "shown as a tip on the knows-linux track" });
});

test("developer steps only for people who code", () => {
    let shown = started(ONLINE, "mac", false).walk();
    ok(!shown.includes("ai-agent") && !shown.includes("dev-basics"));
    shown = started(ONLINE, "mac", true).walk();
    ok(shown.includes("ai-agent") && shown.includes("dev-basics"));
});

test("core path for a Linux user who does not code", () => {
    eq(started(ONLINE, "knows-linux").walk(),
       ["super-key", "menu", "tiling", "workspaces", "shortcuts", "theme", "display", "hardware", "apps", "updates", "finish"]);
});

// Edge case: offline and the user skips step 2

test("offline defers the steps that need internet", () => {
    const r = started(OFFLINE, "new-to-linux", true);
    eq(r.current(), "internet");
    r.skip();
    const shown = r.walk();
    ok(!shown.includes("ai-agent") && !shown.includes("updates"), shown.join(","));
    eq(r.s.steps.updates, { outcome: "deferred", at: NOW, reason: "needs online" });
    eq(E.openSteps(MANIFEST, r.s).map(s => s.id), ["ai-agent", "updates"]);
});

// Edge case: a command is missing or renamed

test("auto-skip records the reason and moves on", () => {
    const r = started(ONLINE);
    const step = r.current();
    r.s = E.autoSkip(MANIFEST, r.s, ONLINE, NOW, "command omarchy-foo is missing");
    eq(r.s.steps[step], { outcome: "auto-skipped", at: NOW, reason: "command omarchy-foo is missing" });
    ok(r.current() !== step);
});

test("failures are listed on the finish screen", () => {
    const r = started(ONLINE);
    const step = r.current();
    r.s = E.failStep(MANIFEST, r.s, ONLINE, NOW, "panel did not open");
    eq(E.openSteps(MANIFEST, r.s).map(s => s.id), [step]);
});

// Edge case: existing user re-running

test("re-run starts at the track picker and keeps results", () => {
    const r = started(ONLINE, "mac");
    r.walk();
    const before = copy(r.s.steps);
    r.s = E.rerun(r.s, false, NOW);
    eq(r.s.status, "in-progress");
    eq(r.current(), "welcome");
    eq(r.s.track, "mac");
    eq(r.s.steps, before);
});

test("re-run of only skipped steps passes over done ones", () => {
    const r = started(ONLINE);
    r.done(); // super-key
    while (r.s.status === "in-progress") r.skip();
    r.s = E.rerun(r.s, true, NOW);
    eq(r.s.mode, "only-skipped");
    r.start();
    eq(r.current(), "welcome", "welcome stays even though it is done");
    r.done();
    eq(r.current(), "menu", "super-key was done");
    const shown = r.walk();
    eq(shown[shown.length - 1], "finish");
    eq(r.s.mode, "full", "completion resets the mode");
});

test("re-run needs a finished or dismissed run", () => {
    throws(() => E.rerun(started(ONLINE).s, false, NOW), "while onboarding is in-progress");
    const r = started(ONLINE);
    r.s = E.rerun(E.dismiss(r.s, NOW), false, NOW);
    eq(r.current(), "welcome");
});

// Replaying one lesson

test("replay shows one step without moving the flow", () => {
    const r = started(ONLINE, "mac");
    r.walk();
    r.s = E.replay(MANIFEST, r.s, "theme", NOW);
    eq(r.current(), "theme");
    r.done();
    eq(r.s.status, "completed");
    eq(r.current(), null);
    eq(r.s.steps.theme.outcome, "done");
});

test("replay during a run returns to the current step", () => {
    const r = started(ONLINE, "mac");
    const step = r.current();
    r.s = E.replay(MANIFEST, r.s, "clipboard", NOW);
    eq(r.current(), "clipboard");
    r.skip();
    eq(r.current(), step);
});

test("replay ignores skip rules and rejects unknown steps", () => {
    eq(E.currentStep(MANIFEST, E.replay(MANIFEST, E.newState(NOW), "internet", NOW)).id, "internet");
    throws(() => E.replay(MANIFEST, E.newState(NOW), "nope", NOW), "unknown step 'nope'");
});

// ================================================================ events

test("parses the events seen live", () => {
    eq(D.parseEvent("openwindow>>62d9b7711630,1,foot,foot"),
       { name: "openwindow", addr: "62d9b7711630", workspace: "1", cls: "foot", title: "foot" });
    eq(D.parseEvent("changefloatingmode>>62d9b7711630,1"), { name: "changefloatingmode", addr: "62d9b7711630", floating: true });
    eq(D.parseEvent("fullscreen>>0"), { name: "fullscreen", on: false });
    eq(D.parseEvent("closelayer>>omarchy-menu"), { name: "closelayer", namespace: "omarchy-menu" });
    eq(D.parseEvent("movewindowv2>>abc,2,2"), { name: "movewindowv2", addr: "abc", workspace: "2" });
    eq(D.parseEvent("workspacev2>>2,2"), { name: "workspacev2", id: "2", workspace: "2" });
});

test("titles keep their commas", () => {
    eq(D.parseEvent("openwindow>>abc,2,chromium,New Tab, Chromium").title, "New Tab, Chromium");
});

test("empty active window and ignored lines", () => {
    eq(D.parseEvent("activewindowv2>>").addr, null);
    eq(D.parseEvent("activewindowv2>>,").addr, null);
    eq(D.parseEvent("activelayout>>kb,English (US)"), null);
    eq(D.parseEvent("garbage"), null);
    eq(D.parseEvent("workspacev2>>2"), null);
    eq(D.parseEvent("fullscreen>>1\n"), { name: "fullscreen", on: true });
});

test("probe output parsers", () => {
    eq([D.parseConnectivity("full\n"), D.parseConnectivity("portal"), D.parseConnectivity("weird")], [true, false, null]);
    eq(D.parseClients('[{"address":"0xabc","workspace":{"id":1,"name":"1"},"at":[10,20],"size":[300,400],"mapped":true},' +
                      '{"address":"0xdef","workspace":{"name":"2"},"at":[0,0],"size":[1,1],"mapped":false}]'),
       [{ addr: "abc", workspace: "1", x: 10, y: 20, width: 300, height: 400 }]);
    eq(D.parseClients("not json"), null);
});

test("terminal and browser classes", () => {
    ["foot", "kitty", "Alacritty", "org.omarchy.btop", "TUI.float"].forEach(c => ok(D.isTerminal(c), c));
    ok(!D.isTerminal("chromium") && !D.isTerminal("footclient-ish"));
    ok(D.isBrowser("chromium") && D.isBrowser("helium", "helium.desktop"));
    ok(!D.isBrowser("chrome-app.hey.com__-Default", "chromium"));
});

// ================================================================ drills

const hypr = line => ({ kind: "hypr", line });
function feed(d, list) { return list.reduce((out, o) => out.concat(d.observe(o)), []); }
const ticks = ids => ids.map(subtask => ({ subtask, ticked: true }));
const client = (addr, x, y, w, h, ws) => ({ addr, workspace: ws || "1", x, y, width: w, height: h });

test("menu opens and closes", () => {
    const d = D.create("menu");
    eq(feed(d, [{ kind: "keybindings", open: false }, hypr("openlayer>>omarchy-menu"), hypr("closelayer>>omarchy-menu")]),
       ticks(["open", "close"]));
    ok(d.complete());
});

test("menu ignores the keybindings list and other layers", () => {
    const d = D.create("menu");
    eq(feed(d, [{ kind: "keybindings", open: true }, hypr("openlayer>>omarchy-menu"), hypr("closelayer>>omarchy-menu"),
                hypr("openlayer>>omarchy-image-selector")]), []);
});

test("shortcuts need the keybindings list", () => {
    const d = D.create("shortcuts");
    eq(feed(d, [{ kind: "keybindings", open: false }, hypr("openlayer>>omarchy-menu")]), []);
    eq(feed(d, [{ kind: "keybindings", open: true }, hypr("openlayer>>omarchy-menu")]), ticks(["open"]));
});

const OPEN_PAIR = [hypr("openwindow>>t1,1,foot,foot"), hypr("activewindowv2>>t1"),
                   hypr("openwindow>>b1,1,chromium,New Tab"), hypr("activewindowv2>>b1")];

test("tiling: full walk", () => {
    const d = D.create("tiling", { defaultBrowser: "chromium" });
    const changes = feed(d, OPEN_PAIR.concat([
        { kind: "clients", windows: [client("t1", 0, 0, 100, 100), client("b1", 100, 0, 100, 100)] },
        { kind: "clients", windows: [client("t1", 0, 0, 200, 50), client("b1", 0, 50, 200, 50)] },
        hypr("activewindowv2>>t1")]));
    eq(changes, ticks(["terminal", "browser", "split", "focus"]));
    ok(d.complete());
});

test("tiling: focusing a new window is not moving focus", () => {
    eq(feed(D.create("tiling"), OPEN_PAIR), ticks(["terminal", "browser"]));
});

test("tiling: focus from an unrelated window does not count", () => {
    const d = D.create("tiling");
    const changes = feed(d, OPEN_PAIR.concat([hypr("activewindowv2>>other"), hypr("activewindowv2>>t1")]));
    ok(!changes.some(c => c.subtask === "focus"));
});

test("tiling: closing a drill window resets only its sub-task", () => {
    const d = D.create("tiling");
    feed(d, OPEN_PAIR.concat([hypr("activewindowv2>>t1")]));
    eq(feed(d, [hypr("closewindow>>b1")]), [{ subtask: "browser", ticked: false }]);
    ok(d.ticked.focus);
    eq(feed(d, [hypr("openwindow>>b2,1,chromium,x")]), ticks(["browser"]));
});

test("tiling: both windows must share a workspace", () => {
    const d = D.create("tiling");
    feed(d, [hypr("openwindow>>t1,1,foot,foot"), hypr("activewindowv2>>t1"), hypr("openwindow>>b1,2,chromium,x"),
             hypr("activewindowv2>>b1"), hypr("activewindowv2>>t1")]);
    ok(!d.complete());
    eq(feed(d, [{ kind: "clients", windows: [client("t1", 0, 0, 100, 100), client("b1", 0, 0, 1, 1, "2")] }]), []);
});

test("window controls need the round trip", () => {
    const d = D.create("window-controls");
    eq(feed(d, [hypr("changefloatingmode>>a,1"), hypr("fullscreen>>1")]), []);
    eq(feed(d, [hypr("changefloatingmode>>a,0"), hypr("fullscreen>>0"), hypr("closewindow>>b")]),
       ticks(["float", "fullscreen", "close"]));
    ok(d.complete());
    eq(feed(D.create("window-controls"), [hypr("changefloatingmode>>a,0"), hypr("fullscreen>>0")]), []);
});

test("workspaces: switch and move", () => {
    eq(feed(D.create("workspaces"), [hypr("workspacev2>>2,2"), hypr("workspacev2>>1,1"), hypr("movewindowv2>>a,2,2")]),
       ticks(["switch", "move"]));
});

test("every drill matches the manifest's sub-tasks", () => {
    D.DRILL_STEPS.forEach(step => {
        const want = MANIFEST.steps.find(s => s.id === step).subtasks.map(t => t.id);
        eq(D.create(step).subtasks, want, step);
    });
    eq(D.create("theme"), null);
});

// ================================================================ ui

test("track copy comes from the step's variant", () => {
    const step = MANIFEST.steps.find(s => s.id === "super-key");
    ok(E.copyFor(step, "mac").screen.includes("⌘"));
    ok(E.copyFor(step, "windows").screen.includes("Windows key"));
    eq(E.copyFor(step, "knows-linux").screen, step.screen);
    eq(E.copyFor(step, null).screen, step.screen);
});

test("variants for unknown tracks or keys are rejected", () => {
    const m = copy(MINIMAL);
    m.steps.splice(1, 0, { id: "x", number: 1, phase: 0, title: "X", done_when: "y", variants: { linux: { screen: "s" } } });
    m.steps[2].number = 2;
    throws(() => E.validateManifest(m), "unknown track 'linux'");
    m.steps[1].variants = { mac: { colour: "red" } };
    throws(() => E.validateManifest(m), "unknown key 'colour'");
});

test("key caps", () => {
    eq(U.keyCaps("Super + Shift + Return"), ["Super", "Shift", "Return"]);
    eq(U.keyCaps("Super + Arrows"), ["Super", "←", "↑", "↓", "→"]);
    eq(U.keyCaps("Esc"), ["Esc"]);
    eq(U.keyCaps(""), []);
});

test("a plus between keys, but not between arrows", () => {
    eq(U.keyCapItems("Super + J").map(c => c.plus), [false, true]);
    eq(U.keyCapItems("Super + Arrows").map(c => c.label + (c.plus ? "+" : "")), ["Super", "←+", "↑", "↓", "→"]);
});

test("every drill sub-task names its keys", () => {
    D.DRILL_STEPS.concat(["clipboard"]).forEach(id => {
        MANIFEST.steps.find(s => s.id === id).subtasks.forEach(t => ok(U.keyCaps(t.keys).length > 0, id + "/" + t.id));
    });
});

test("idle hints at 20 s and 40 s", () => {
    eq([0, 19999, 20000, 39999, 40000, 90000].map(U.hintLevel), [0, 0, 1, 1, 2, 2]);
});

test("centered steps take the keyboard; drills and panel steps stay in the corner", () => {
    ok(U.isCentered("welcome") && U.isCentered("super-key") && U.isCentered("theme") && U.isCentered("finish"));
    D.DRILL_STEPS.concat(["clipboard", "internet", "display", "hardware", "apps", "updates"]).forEach(id => ok(!U.isCentered(id), id));
});

test("a missing command auto-skips its step and names it", () => {
    const facts = { online: false, owner_setup_deferred: false, missing: ["omarchy theme set"] };
    const r = started(facts, "knows-linux");
    const shown = r.walk();
    ok(!shown.includes("theme"), shown.join(","));
    eq(r.s.steps.theme, { outcome: "auto-skipped", at: NOW, reason: "command 'omarchy theme set' is missing" });
});

test("every requirement is collected once", () => {
    const all = E.allRequirements(MANIFEST);
    ok(all.includes("omarchy theme set") && all.includes("omarchy update") && all.includes("nmcli"));
    eq(all.length, new Set(all).size);
});

test("requires must be a list of commands", () => {
    const m = copy(MINIMAL);
    m.steps.splice(1, 0, { id: "x", number: 1, phase: 0, title: "X", done_when: "y", requires: "nmcli" });
    m.steps[2].number = 2;
    throws(() => E.validateManifest(m), "requires must be a list");
});

test("hardware items follow detection and available commands", () => {
    eq(U.hardwareItems({ bluetooth: true, fingerprint: false }).map(i => i.id), ["audio", "bluetooth", "firmware"]);
    eq(U.hardwareItems({ bluetooth: false, fingerprint: true, missing: ["pw-play"] }).map(i => i.id), ["fingerprint", "firmware"]);
    ok(U.hardwareItems({}).filter(i => i.action.startsWith("run:")).every(i => i.confirm), "system changes ask first");
});

function argvs(plan) { return plan.run.map(s => s.argv.join(" ")); }

test("do it for me: menu opens then closes", () => {
    eq(argvs(U.doItPlan("menu", { ticked: {} })), ["omarchy-menu toggle", "omarchy-menu toggle"]);
    eq(argvs(U.doItPlan("menu", { ticked: { open: true } })), ["omarchy-menu toggle"]);
});

test("do it for me: tiling works through its sub-tasks in order", () => {
    const w = { terminal: "t1", browser: "b1", active: "b1" };
    eq(argvs(U.doItPlan("tiling", { ticked: {}, windows: {} })), ["omarchy-launch-terminal"]);
    eq(argvs(U.doItPlan("tiling", { ticked: { terminal: true }, windows: {} })), ["omarchy-launch-browser"]);
    eq(argvs(U.doItPlan("tiling", { ticked: { terminal: true, browser: true }, windows: w })),
       ["hyprctl dispatch hl.dsp.focus({ window = 'address:0xt1' })", 'hyprctl dispatch hl.dsp.layout("togglesplit")']);
    eq(argvs(U.doItPlan("tiling", { ticked: { terminal: true, browser: true, split: true }, windows: w })),
       ["hyprctl dispatch hl.dsp.focus({ window = 'address:0xt1' })"]);
});

test("do it for me never touches windows it doesn't know", () => {
    eq(U.doItPlan("tiling", { ticked: { terminal: true, browser: true }, windows: {} }), { special: "skip" });
    eq(U.doItPlan("window-controls", { ticked: {}, windows: {} }), { special: "skip" });
    eq(U.doItPlan("window-controls", { ticked: { float: true, fullscreen: true }, windows: { terminal: "t1" } }), { special: "skip" });
    eq(U.doItPlan("workspaces", { ticked: { switch: true }, windows: {} }), { special: "skip" });
});

test("do it for me: window controls and workspaces", () => {
    const w = { terminal: "t1", browser: "b1" };
    eq(argvs(U.doItPlan("window-controls", { ticked: {}, windows: w })).length, 3);
    eq(argvs(U.doItPlan("window-controls", { ticked: { float: true, fullscreen: true }, windows: w })),
       ["hyprctl dispatch hl.dsp.window.close({ window = 'address:0xb1' })"]);
    eq(argvs(U.doItPlan("workspaces", { ticked: {}, workspace: 3 })),
       ["hyprctl dispatch hl.dsp.focus({ workspace = '4' })", "hyprctl dispatch hl.dsp.focus({ workspace = '3' })"]);
    eq(argvs(U.doItPlan("workspaces", { ticked: { switch: true }, windows: w, workspace: 9 }))[1],
       "hyprctl dispatch hl.dsp.window.move({ workspace = '8' })");
});

test("do it for me: the network panel and display", () => {
    eq(argvs(U.doItPlan("internet", {})), ["omarchy-shell shell toggle omarchy.network"]);
    eq(argvs(U.doItPlan("display", { ticked: {} })), ["omarchy-hyprland-monitor-scaling up", "omarchy-hyprland-monitor-scaling down"]);
    eq(argvs(U.doItPlan("display", { ticked: { scale: true } })), ["omarchy-toggle-nightlight", "omarchy-toggle-nightlight"]);
});

test("do it for me: specials and steps without one", () => {
    eq(U.doItPlan("super-key", {}), { special: "complete" });
    eq(U.doItPlan("clipboard", {}), { special: "fill" });
    eq(U.doItPlan("theme", {}), null);
});

test("the tiling drill reports its own windows", () => {
    const d = D.create("tiling");
    feed(d, OPEN_PAIR);
    eq(d.windows(), { terminal: "t1", browser: "b1", active: "b1" });
});

// ================================================================ developer track (M5)

test("agent notes only where known", () => {
    ok(U.agentNote("claude").includes("Anthropic"));
    eq(U.agentNote("muse"), "");
});

test("email validation", () => {
    ok(U.validEmail("a@b.co") && U.validEmail("  first.last@example.org "));
    ok(!U.validEmail("") && !U.validEmail("no-at.example.com") && !U.validEmail("a@b") && !U.validEmail("a b@c.de"));
});

test("git and ssh-keygen commands", () => {
    eq(U.gitConfigArgvs(" Ada Lovelace ", "ada@example.org "), [
        ["git", "config", "--global", "user.name", "Ada Lovelace"],
        ["git", "config", "--global", "user.email", "ada@example.org"]]);
    eq(U.sshKeygenArgv("/home/ada", "ada@example.org"),
       ["ssh-keygen", "-t", "ed25519", "-C", "ada@example.org", "-f", "/home/ada/.ssh/id_ed25519", "-N", ""]);
});

test("editor tip mentions LazyVim only for Neovim", () => {
    ok(U.editorTip("nvim").includes("LazyVim"));
    ok(U.editorTip("").includes("LazyVim"), "Omarchy's fallback editor is nvim");
    ok(!U.editorTip("zeditor").includes("LazyVim") && U.editorTip("zeditor").includes("zeditor"));
});

test("developer steps declare what they run", () => {
    eq(MANIFEST.steps.find(s => s.id === "ai-agent").requires, ["omarchy default agent"]);
    eq(MANIFEST.steps.find(s => s.id === "dev-basics").subtasks.map(t => t.id), ["git", "ssh", "editor"]);
});

// ================================================================ recordings

function recording(name) {
    return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8").split("\n")
        .map(l => l.trim()).filter(l => l && !l.startsWith("#")).map(l => JSON.parse(l));
}

function replay(name, from) {
    const w = D.walker({ defaultBrowser: "chromium" }, from);
    const events = [];
    recording(name).forEach(obs => { events.push(...w.feed(obs)); });
    return { w, events };
}

// The M2 done condition, from a live walkthrough on Omarchy 4.0.4: every
// drill sub-task ticks, in order, with no resets.
test("live walkthrough ticks every drill sub-task", () => {
    const { w, events } = replay("walkthrough-4.0.4.jsonl");
    ok(w.done(), "all drills complete");
    D.DRILL_STEPS.forEach(step => {
        MANIFEST.steps.find(s => s.id === step).subtasks.forEach(t => {
            ok(events.some(e => e.type === "tick" && e.step === step && e.subtask === t.id && e.ticked), step + "/" + t.id);
        });
    });
    ok(!events.some(e => e.type === "tick" && !e.ticked), "no resets");
    eq(events.filter(e => e.type === "complete").map(e => e.step), D.DRILL_STEPS);
});

// The same walkthrough, recorded by the plugin through Quickshell rather than
// by reading socket2 directly.
test("plugin-recorded walkthrough ticks every drill sub-task", () => {
    const { w, events } = replay("walkthrough-plugin-4.0.4.jsonl");
    ok(w.done(), "all drills complete");
    ok(!events.some(e => e.type === "tick" && !e.ticked), "no resets");
    eq(events.filter(e => e.type === "complete").map(e => e.step), D.DRILL_STEPS);
});

test("synthetic walkthrough completes too", () => {
    ok(replay("synthetic-drills.jsonl").w.done());
});

test("a short recording stops at the unfinished drill", () => {
    const { w } = replay("menu-open-only.jsonl");
    ok(!w.done());
    eq(w.drill.step, "menu");
    eq(Object.keys(w.drill.ticked), ["open"]);
});

test("the walker can start later and rejects non-drills", () => {
    eq(D.walker({}, "shortcuts").drill.step, "shortcuts");
    throws(() => D.walker({}, "theme"), "'theme' is not a drill");
});

// ================================================================

console.log(passed + " passed, " + failed + " failed");
process.exit(failed ? 1 : 0);
