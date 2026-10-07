.pragma library

// The onboarding state machine: which step is current, what finishing or
// skipping a step does, and what to do at login. Pure functions over plain
// objects so node can test them; every function that changes the state
// returns a new object and never mutates its input. Errors are thrown as
// Error objects whose message is ready to show.
//
// The flow: the welcome checklist (Wi-Fi, update, keybindings), then either
// Close, which finishes onboarding, or the tutorial, which walks the steps
// after it and ends on the finish screen.
//
// steps.json, per step:
//   id, number (0-based, in order), phase, title, goal, screen, done_when,
//   keys, subtasks [{id, label, keys}],
//   remember [{label, keys}]  keys to show, not tasks (the finish screen)
//   link {text, label, url}   a page to open, as Omarchy's menu does (a web app)
//   outro      a last line, after everything else on the card
//   cheer      what Omi says, in place of the title, when the step is done
//   skip_if   auto-skip when any listed fact is true
//   show_if   auto-skip unless every listed fact is true
//   needs     defer (stays pending) while any listed fact is false
//   requires  commands the step runs, as omarchy routes ("omarchy theme set")
//             or programs ("nmcli"); facts.missing lists the ones not on this
//             machine, and a step that needs one is auto-skipped with the
//             command named in its reason
//
// Facts: online. A fact detection hasn't checked is null: skip_if and show_if
// need a confirmed true, needs a confirmed false.

var WELCOME = "welcome";
var FINISH = "finish";
var STATE_VERSION = 1;

var FACTS = ["online"];
var STEP_KEYS = ["id", "number", "phase", "title", "goal", "screen", "done_when",
                 "skip_if", "show_if", "needs", "requires", "subtasks", "keys", "remember", "link", "outro", "cheer"];
var SUBTASK_KEYS = ["id", "label", "keys"];

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
        if (step.requires !== undefined && (!Array.isArray(step.requires) || step.requires.some(function (r) { return typeof r !== "string" || !r; })))
            fail("invalid manifest: step '" + step.id + "' requires must be a list of commands");
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
    return ["skip_if", "show_if", "needs", "requires"].some(function (k) { return (step[k] || []).length > 0; });
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
        current: null,
        mode: "full",
        replay: null,
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
    // From the old "Remind me later", which is gone.
    delete s.pause_notified;
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

// Every command any step requires, for one availability check at startup.
function allRequirements(m) {
    var out = [];
    m.steps.forEach(function (step) {
        (step.requires || []).forEach(function (r) { if (out.indexOf(r) < 0) out.push(r); });
    });
    return out;
}

// Steps the finish screen lists as still to do: skipped, deferred or failed.
function openSteps(m, s) {
    return m.steps.filter(function (step) {
        var o = outcome(s, step.id);
        return o === "skipped" || o === "deferred" || o === "failed";
    });
}

// The step before the current one that the user saw (done, skipped or
// failed), which Back returns to. null when there is none, or in a replay.
function previousStep(m, s) {
    if (s.replay || s.status !== "in-progress" || !s.current) return null;
    for (var i = indexOf(m, s.current) - 1; i >= 0; i--) {
        var o = outcome(s, m.steps[i].id);
        if (o === "done" || o === "skipped" || o === "failed") return m.steps[i].id;
    }
    return null;
}

// The tutorial's steps: everything between the welcome checklist and the
// finish screen.
function tutorialSteps(m) {
    return m.steps.slice(1, m.steps.length - 1);
}

// ---------------------------------------------------------------- transitions

// What to do when the user logs in: {action, step, state}. Action is start,
// resume (with step) or nothing. Onboarding only comes up by itself on the
// first login, or to finish a run the session ended in the middle of; after
// that it's run by hand. A "paused" state, left by older builds, stays quiet.
function login(s, now) {
    var next = clone(s);
    switch (s.status) {
    case "not-started": return { action: "start", step: null, state: next };
    case "in-progress": return { action: "resume", step: s.current || WELCOME, state: next };
    default: return { action: "nothing", step: null, state: next };
    }
}

// Opens onboarding: starts fresh, resumes a run left paused by an older
// build, or re-checks the current step of a run in progress (it may have
// been done meanwhile).
function start(m, s, facts, now) {
    var next = clone(s);
    if (s.status === "completed" || s.status === "dismissed") fail("cannot start while onboarding is " + s.status);
    if (s.status === "not-started" || !next.current) next.current = WELCOME;
    next.status = "in-progress";
    settle(m, next, facts, now);
    next.updated_at = now;
    return next;
}

// On the welcome checklist, "Start the tutorial" completes it and moves on;
// on any other step, the step is done.
function complete(m, s, facts, now) { return finishCurrent(m, s, facts, now, "done", null); }
function skip(m, s, facts, now) { return finishCurrent(m, s, facts, now, "skipped", null); }
function failStep(m, s, facts, now, reason) { return finishCurrent(m, s, facts, now, "failed", reason); }
// Used by actions, e.g. when a step's command is missing.
function autoSkip(m, s, facts, now, reason) { return finishCurrent(m, s, facts, now, "auto-skipped", reason); }

// "Close" on the welcome checklist: onboarding is finished without the
// tutorial, which stays available to re-run.
function finishNow(s, now) {
    requireRunning(s, "close the welcome screen");
    if (s.current !== WELCOME || s.replay) fail("only the welcome screen can be closed this way");
    var next = clone(s);
    record(next, WELCOME, "done", null, now);
    next.status = "completed";
    next.current = null;
    next.mode = "full";
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

// Back to the previous step the user saw, to do it again: its result is
// forgotten so it can be recorded afresh.
function back(m, s, now) {
    var prev = previousStep(m, s);
    if (!prev) fail("nothing to go back to");
    var next = clone(s);
    delete next.steps[prev];
    next.current = prev;
    next.updated_at = now;
    return next;
}

// From the finish screen, through the steps still to do (openSteps): the
// done ones are passed over, as in a re-run of only skipped steps, and the
// flow ends on the finish screen again.
function redoOpen(m, s, facts, now) {
    requireRunning(s, "redo steps");
    if (s.current !== FINISH) fail("can only redo steps from the finish screen");
    if (!openSteps(m, s).length) fail("nothing left to do");
    var next = clone(s);
    next.mode = "only-skipped";
    advanceFrom(m, next, facts, now, 1);
    next.updated_at = now;
    return next;
}

// Running onboarding again: back to the welcome checklist with past results
// kept. onlySkipped passes over tutorial steps already done.
function rerun(s, onlySkipped, now) {
    if (s.status !== "completed" && s.status !== "dismissed") fail("cannot re-run while onboarding is " + s.status);
    var next = clone(s);
    next.status = "in-progress";
    next.current = WELCOME;
    next.mode = onlySkipped ? "only-skipped" : "full";
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
        var verdict = evaluate(step, facts);
        if (verdict.show) {
            s.current = step.id;
            return;
        }
        record(s, step.id, verdict.outcome, verdict.reason, now);
    }
    // validateManifest guarantees finish is last and always shown.
    fail("finish step was not shown");
}

function evaluate(step, facts) {
    var i, f;
    for (i = 0; i < (step.show_if || []).length; i++) {
        f = step.show_if[i];
        if (factValue(f, facts) !== true)
            return { show: false, outcome: "auto-skipped", reason: "not applicable (" + f + " is not true)" };
    }
    for (i = 0; i < (step.skip_if || []).length; i++) {
        f = step.skip_if[i];
        if (factValue(f, facts) === true) return { show: false, outcome: "auto-skipped", reason: "already " + f };
    }
    var missing = (facts && facts.missing) || [];
    for (i = 0; i < (step.requires || []).length; i++) {
        if (missing.indexOf(step.requires[i]) >= 0)
            return { show: false, outcome: "auto-skipped", reason: "command '" + step.requires[i] + "' is missing" };
    }
    for (i = 0; i < (step.needs || []).length; i++) {
        f = step.needs[i];
        if (factValue(f, facts) === false) return { show: false, outcome: "deferred", reason: "needs " + f };
    }
    return { show: true };
}

function factValue(fact, facts) {
    facts = facts || {};
    switch (fact) {
    case "online": return facts.online === undefined ? null : facts.online;
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
