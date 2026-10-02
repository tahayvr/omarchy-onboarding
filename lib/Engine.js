.pragma library

// The onboarding state machine: which step is current, what finishing or
// skipping a step does, and what to do at login. Pure functions over plain
// objects so node can test them; every function that changes the state
// returns a new object and never mutates its input. Errors are thrown as
// Error objects whose message is ready to show.
//
// steps.json, per step:
//   id, number (0-based, in order), phase, title, core, goal, screen, tip,
//   done_when, subtasks [{id, label}]
//   skip_if     auto-skip when any listed fact is true
//   show_if     auto-skip unless every listed fact is true
//   needs       defer (stays pending) while any listed fact is false
//   hide_tracks tracks that get `tip` instead of the step
//
// Facts: online, owner-setup-deferred, writes-code. A fact detection hasn't
// checked is null: skip_if and show_if need a confirmed true, needs a
// confirmed false.

var WELCOME = "welcome";
var FINISH = "finish";
var STATE_VERSION = 1;

var TRACKS = ["new-to-linux", "mac", "windows", "knows-linux"];
var FACTS = ["online", "owner-setup-deferred", "writes-code"];
var STEP_KEYS = ["id", "number", "phase", "title", "core", "goal", "screen", "tip", "done_when",
                 "skip_if", "show_if", "needs", "hide_tracks", "subtasks", "keys", "variants"];
var SUBTASK_KEYS = ["id", "label", "keys"];
// Copy a track may override: variants: {"mac": {"screen": "..."}}.
var VARIANT_KEYS = ["title", "goal", "screen"];

// ---------------------------------------------------------------- manifest

function fail(message) {
    throw new Error(message);
}

function isKebab(s) {
    return typeof s === "string" && /^[a-z0-9]+(-[a-z0-9]+)*$/.test(s);
}

// Checks steps.json and returns it. Unknown keys and facts are rejected so a
// typo fails at load instead of silently dropping a rule.
function validateManifest(m) {
    if (!m || !Array.isArray(m.phases) || !Array.isArray(m.steps) || m.steps.length === 0)
        fail("invalid manifest: needs phases and steps");
    var phases = {};
    m.phases.forEach(function (p) { phases[p.number] = true; });

    var first = m.steps[0], last = m.steps[m.steps.length - 1];
    if (first.id !== WELCOME) fail("invalid manifest: first step must be '" + WELCOME + "', found '" + first.id + "'");
    if (last.id !== FINISH) fail("invalid manifest: last step must be '" + FINISH + "', found '" + last.id + "'");

    var seen = {};
    m.steps.forEach(function (step, i) {
        Object.keys(step).forEach(function (key) {
            if (STEP_KEYS.indexOf(key) < 0) fail("invalid manifest: step '" + step.id + "' has unknown key '" + key + "'");
        });
        if (!isKebab(step.id)) fail("invalid manifest: step id '" + step.id + "' must be lowercase kebab-case");
        if (seen[step.id]) fail("invalid manifest: duplicate step id '" + step.id + "'");
        seen[step.id] = true;
        if (step.number !== i) fail("invalid manifest: step '" + step.id + "' has number " + step.number + ", expected " + i);
        if (!phases[step.phase]) fail("invalid manifest: step '" + step.id + "' uses unknown phase " + step.phase);
        if (typeof step.title !== "string" || typeof step.done_when !== "string")
            fail("invalid manifest: step '" + step.id + "' needs a title and done_when");
        ["skip_if", "show_if", "needs"].forEach(function (rule) {
            (step[rule] || []).forEach(function (fact) {
                if (FACTS.indexOf(fact) < 0) fail("invalid manifest: step '" + step.id + "' uses unknown fact '" + fact + "'");
            });
        });
        (step.hide_tracks || []).forEach(function (track) {
            if (TRACKS.indexOf(track) < 0) fail("invalid manifest: step '" + step.id + "' uses unknown track '" + track + "'");
        });
        if ((step.hide_tracks || []).length && !step.tip) fail("invalid manifest: step '" + step.id + "' hides tracks but has no tip");
        Object.keys(step.variants || {}).forEach(function (track) {
            if (TRACKS.indexOf(track) < 0) fail("invalid manifest: step '" + step.id + "' has a variant for unknown track '" + track + "'");
            Object.keys(step.variants[track]).forEach(function (key) {
                if (VARIANT_KEYS.indexOf(key) < 0) fail("invalid manifest: step '" + step.id + "' variant '" + track + "' has unknown key '" + key + "'");
            });
        });
        var subtaskIds = {};
        (step.subtasks || []).forEach(function (t) {
            Object.keys(t).forEach(function (key) {
                if (SUBTASK_KEYS.indexOf(key) < 0) fail("invalid manifest: step '" + step.id + "' subtask '" + t.id + "' has unknown key '" + key + "'");
            });
            if (subtaskIds[t.id]) fail("invalid manifest: step '" + step.id + "' repeats subtask '" + t.id + "'");
            subtaskIds[t.id] = true;
        });
    });

    // The engine relies on these two always being shown.
    [first, last].forEach(function (step) {
        if (hasRules(step)) fail("invalid manifest: step '" + step.id + "' cannot have skip rules");
    });
    return m;
}

function hasRules(step) {
    return ["skip_if", "show_if", "needs", "hide_tracks"].some(function (k) { return (step[k] || []).length > 0; });
}

function stepById(m, id) {
    for (var i = 0; i < m.steps.length; i++) if (m.steps[i].id === id) return m.steps[i];
    return null;
}

function indexOf(m, id) {
    for (var i = 0; i < m.steps.length; i++) if (m.steps[i].id === id) return i;
    return -1;
}

// ---------------------------------------------------------------- state

function newState(now) {
    return {
        version: STATE_VERSION,
        status: "not-started",
        track: null,
        writes_code: false,
        current: null,
        mode: "full",
        replay: null,
        pause_notified: false,
        steps: {},
        created_at: now,
        updated_at: now
    };
}

// Parses the state file's text. Empty text is a fresh state. Throws on JSON
// errors or an unknown version, so callers decide whether to quarantine it.
function parseState(text, now) {
    if (!text || !String(text).trim()) return newState(now);
    var s;
    try {
        s = JSON.parse(text);
    } catch (e) {
        fail("state file is corrupt: " + e.message);
    }
    if (!s || typeof s !== "object") fail("state file is corrupt: not an object");
    if (s.version !== STATE_VERSION) fail("state file has version " + s.version + "; this build understands " + STATE_VERSION);
    var fresh = newState(now);
    Object.keys(fresh).forEach(function (k) { if (s[k] === undefined) s[k] = fresh[k]; });
    return s;
}

function serialize(s) {
    return JSON.stringify(s, null, 2) + "\n";
}

function clone(s) {
    return JSON.parse(JSON.stringify(s));
}

function outcome(s, id) {
    return s.steps[id] ? s.steps[id].outcome : null;
}

// ---------------------------------------------------------------- queries

// The step on screen: a replayed lesson first, otherwise the current step.
function currentStep(m, s) {
    if (s.replay) return stepById(m, s.replay);
    if (s.status === "in-progress" && s.current) return stepById(m, s.current);
    return null;
}

// A step's copy for a track: the step with its variant for that track applied.
function copyFor(step, track) {
    var out = {};
    Object.keys(step).forEach(function (k) { out[k] = step[k]; });
    var variant = track && step.variants ? step.variants[track] : null;
    if (variant) Object.keys(variant).forEach(function (k) { out[k] = variant[k]; });
    return out;
}

// Steps the finish screen lists as still open: deferred or failed.
function openSteps(m, s) {
    return m.steps.filter(function (step) {
        var o = outcome(s, step.id);
        return o === "deferred" || o === "failed";
    });
}

// ---------------------------------------------------------------- transitions

// What to do when the user logs in: {action, step, state}. Action is start,
// resume (with step), remind (paused, once) or nothing.
function login(s, now) {
    var next = clone(s);
    switch (s.status) {
    case "not-started": return { action: "start", step: null, state: next };
    case "in-progress": return { action: "resume", step: s.current || WELCOME, state: next };
    case "paused":
        if (!s.pause_notified) {
            next.pause_notified = true;
            next.updated_at = now;
            return { action: "remind", step: null, state: next };
        }
        return { action: "nothing", step: null, state: next };
    default: return { action: "nothing", step: null, state: next };
    }
}

// Opens onboarding: starts fresh, resumes a paused run, or re-checks the
// current step of a run in progress (it may have been done meanwhile).
function start(m, s, facts, now) {
    var next = clone(s);
    if (s.status === "completed" || s.status === "dismissed") fail("cannot start while onboarding is " + s.status);
    if (s.status === "not-started" || !next.current) next.current = WELCOME;
    next.status = "in-progress";
    next.pause_notified = false;
    settle(m, next, facts, now);
    next.updated_at = now;
    return next;
}

function chooseTrack(s, track, writesCode, now) {
    requireRunning(s, "pick a track");
    if (s.current !== WELCOME) fail("the track can only be picked on the welcome step");
    if (TRACKS.indexOf(track) < 0) fail("unknown track '" + track + "' (expected one of: " + TRACKS.join(", ") + ")");
    var next = clone(s);
    next.track = track;
    next.writes_code = !!writesCode;
    next.updated_at = now;
    return next;
}

function complete(m, s, facts, now) { return finishCurrent(m, s, facts, now, "done", null); }
function skip(m, s, facts, now) { return finishCurrent(m, s, facts, now, "skipped", null); }
function failStep(m, s, facts, now, reason) { return finishCurrent(m, s, facts, now, "failed", reason); }
// Used by actions, e.g. when a step's command is missing.
function autoSkip(m, s, facts, now, reason) { return finishCurrent(m, s, facts, now, "auto-skipped", reason); }

// "Remind me later".
function pause(s, now) {
    requireRunning(s, "pause");
    var next = clone(s);
    next.status = "paused";
    next.pause_notified = false;
    next.replay = null;
    next.updated_at = now;
    return next;
}

// Quit for good. Reachable from any step, and before starting.
function dismiss(s, now) {
    if (s.status === "completed") fail("cannot dismiss while onboarding is completed");
    var next = clone(s);
    next.status = "dismissed";
    next.current = null;
    next.replay = null;
    next.updated_at = now;
    return next;
}

// An existing user running onboarding again: back to the track picker with
// past results kept. onlySkipped passes over steps already done.
function rerun(s, onlySkipped, now) {
    if (s.status !== "completed" && s.status !== "dismissed") fail("cannot re-run while onboarding is " + s.status);
    var next = clone(s);
    next.status = "in-progress";
    next.current = WELCOME;
    next.mode = onlySkipped ? "only-skipped" : "full";
    next.pause_notified = false;
    next.replay = null;
    next.updated_at = now;
    return next;
}

// `omarchy onboarding --step <id>`: one lesson without moving the flow.
// Rules are ignored because the user asked for this step by name.
function replay(m, s, id, now) {
    if (!stepById(m, id)) fail("unknown step '" + id + "'");
    var next = clone(s);
    next.replay = id;
    next.updated_at = now;
    return next;
}

// ---------------------------------------------------------------- internals

function finishCurrent(m, s, facts, now, result, reason) {
    var next = clone(s);
    if (next.replay) {
        record(next, next.replay, result, reason, now);
        next.replay = null;
        next.updated_at = now;
        return next;
    }
    requireRunning(s, "finish a step");
    var id = next.current || WELCOME;
    if (id === WELCOME && !next.track) fail("pick a track before leaving the welcome step");
    record(next, id, result, reason, now);
    if (id === FINISH) {
        next.status = "completed";
        next.current = null;
        next.mode = "full";
    } else {
        advanceFrom(m, next, facts, now, indexOf(m, id) + 1);
    }
    next.updated_at = now;
    return next;
}

// Re-checks the current step and moves past it if a rule now skips it.
function settle(m, s, facts, now) {
    var i = indexOf(m, s.current);
    if (i < 0) {
        s.current = WELCOME;
        return;
    }
    advanceFrom(m, s, facts, now, i);
}

// Makes the first step at or after `from` that should be shown current,
// recording why each step before it was passed over.
function advanceFrom(m, s, facts, now, from) {
    for (var i = from; i < m.steps.length; i++) {
        var step = m.steps[i];
        var alwaysShown = step.id === WELCOME || step.id === FINISH;
        if (s.mode === "only-skipped" && outcome(s, step.id) === "done" && !alwaysShown) continue;
        var verdict = evaluate(step, s, facts);
        if (verdict.show) {
            s.current = step.id;
            return;
        }
        record(s, step.id, verdict.outcome, verdict.reason, now);
    }
    // validateManifest guarantees finish is last and always shown.
    fail("finish step was not shown");
}

function evaluate(step, s, facts) {
    if (s.track && (step.hide_tracks || []).indexOf(s.track) >= 0)
        return { show: false, outcome: "auto-skipped", reason: "shown as a tip on the " + s.track + " track" };
    var i, f;
    for (i = 0; i < (step.show_if || []).length; i++) {
        f = step.show_if[i];
        if (factValue(f, s, facts) !== true)
            return { show: false, outcome: "auto-skipped", reason: "not applicable (" + f + " is not true)" };
    }
    for (i = 0; i < (step.skip_if || []).length; i++) {
        f = step.skip_if[i];
        if (factValue(f, s, facts) === true) return { show: false, outcome: "auto-skipped", reason: "already " + f };
    }
    for (i = 0; i < (step.needs || []).length; i++) {
        f = step.needs[i];
        if (factValue(f, s, facts) === false) return { show: false, outcome: "deferred", reason: "needs " + f };
    }
    return { show: true };
}

function factValue(fact, s, facts) {
    facts = facts || {};
    switch (fact) {
    case "online": return facts.online === undefined ? null : facts.online;
    case "owner-setup-deferred": return facts.owner_setup_deferred === undefined ? null : facts.owner_setup_deferred;
    case "writes-code": return !!s.writes_code;
    default: return null;
    }
}

function record(s, id, result, reason, now) {
    var entry = { outcome: result, at: now };
    if (reason) entry.reason = reason;
    s.steps[id] = entry;
}

function requireRunning(s, action) {
    if (s.status !== "in-progress") fail("cannot " + action + " while onboarding is " + s.status);
}
