import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "ui"
import "lib/Engine.js" as Engine
import "lib/Drills.js" as Drills
import "lib/Ui.js" as Ui

// The onboarding overlay. It owns the flow while open: loads the state file,
// shows the welcome checklist, runs the tutorial's drills against Hyprland's
// events, and saves every change. The logic lives in lib/; the views in ui/.
//
// Two windows, never both: a centered card that takes the keyboard (the
// welcome checklist, the Super key, the theme picker, finish, and dialogs),
// and a corner card for the drills that leaves the keyboard to Hyprland. When
// the checklist hands over to a panel, a terminal or the keybindings list, it
// steps aside to the corner until that's done.
//
// Payload (summon): {"state": path, "step": id, "onlySkipped": bool, "record": path,
//                    "dryRun": bool, "facts": {...}}
//   state        state file instead of ~/.local/state/omarchy/onboarding.json
//   step         replay one lesson (omarchy-onboarding --step)
//   onlySkipped  when re-running, pass over steps already done
//   record       also save every observation, for replay tests
//   dryRun       log system changes (theme, updates, installs) instead of running them
//   facts        pin facts, for testing: {"online": false} keeps the checklist
//                offline whatever the network says, {"update": "available"}
//                pins the update check
//
// Calls (omarchy-shell shell call <id> <fn> <arg>): startTutorial,
// closeWelcome, connect, update, showKeybindings, next, skip, pause, dismiss,
// doIt, info.
Item {
    id: root

    property string omarchyPath: ""
    property var shell: null
    property var manifest: null

    readonly property string pluginId: manifest && manifest.id ? manifest.id : "tahayvr.onboarding"
    readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace(/^file:\/\//, ""))
    readonly property string defaultStatePath: Quickshell.env("HOME") + "/.local/state/omarchy/onboarding.json"

    property bool opened: false
    property var steps: null
    property string statePath: defaultStatePath
    // The engine state. `state` itself belongs to Item.
    property var flow: null
    property var facts: ({ online: null, missing: [] })
    property string defaultBrowser: ""
    // Where Omarchy's bar is (shell.json), for the workspaces card.
    property string barPosition: "top"
    property string error: ""
    property var pendingPayload: null

    property var drill: null
    property var ticked: ({})
    // The tiling drill's terminal and browser, kept for the later drills and
    // "Do it for me", which only ever act on these.
    property var drillWindows: ({})
    // The workspace a drill began on: "Do it for me" comes back to it.
    property int drillHome: 1
    property double startedAt: 0

    // Esc or ✕ shows the pause dialog over whatever step is current.
    property bool pausing: false
    // A pending "are you sure?" for a system change: {question, confirmText, run}.
    property var confirm: null
    property bool dryRun: false
    property var factsOverride: ({})
    property var marked: ({})

    // The welcome checklist.
    property string ssid: ""
    property string updateStatus: ""
    property bool updating: false
    // What the checklist stepped aside for: "", "wifi", "update" or "keys".
    property string away: ""
    readonly property var checklist: Ui.welcomeChecklist({
        online: facts.online === true,
        ssid: ssid,
        update: updating ? "updating" : updateStatus
    })

    // The tutorial's action steps. The theme step watches the current theme
    // against what it was when the step began.
    property string themeBaseline: ""
    property var monitors: []
    // The last scales read, to tell scaling up from scaling down.
    property var lastScales: null
    property string sunsetBaseline: ""
    property bool sunsetSeen: false
    property var apps: []
    property var appsTried: ({})
    property string preparedStep: ""

    // Idle tracking for the 20 s and 40 s hints.
    property double lastProgress: 0
    property double clock: 0
    readonly property int hint: opened && step ? Ui.hintLevel(clock - lastProgress) : 0

    property var doItQueue: []

    // Observations wait here while the keybindings probe runs, so the
    // probe's answer reaches the drills before the layer event it belongs to.
    property var queue: []
    property bool probing: false
    property var lastClients: null

    property string recordPath: ""
    property var recordLines: []
    property var logLines: []

    readonly property var step: flow && steps ? Engine.currentStep(steps, flow) : null
    readonly property bool centered: away === "" && (pausing || confirm !== null || error !== ""
                                                     || (step !== null && Ui.isCentered(step.id)))
    // Ctrl + / skips while a tutorial step is up. It's a Hyprland
    // bind (bin/onboarding-skip-bind), because the corner card never takes the
    // keyboard. skipKey is "" when the user has the combo bound to something else.
    readonly property bool skipBindWanted: opened && flow !== null && step !== null
                                           && step.id !== "welcome" && step.id !== "finish"
                                           && away === "" && !pausing && confirm === null && error === ""
    property string skipKey: ""
    onSkipBindWantedChanged: setSkipBind()
    // A shell restart mid-tutorial leaves the bind behind.
    Component.onCompleted: setSkipBind()

    function setSkipBind() {
        skipBinder.running = false;
        skipBinder.command = [pluginDir + "/bin/onboarding-skip-bind", skipBindWanted ? "on" : "off"];
        skipBinder.running = true;
    }

    // Omi on every card but the welcome page (which follows its checklist).
    readonly property string omiMode: Ui.cardOmi({
        stepId: step ? step.id : "",
        hint: hint,
        doingIt: doItQueue.length > 0,
        pausing: pausing,
        confirm: confirm !== null,
        error: error,
        away: away
    })
    // Whichever Omi is on screen plays this on top of omiMode for a moment.
    signal omiReacted(string mode)
    function omiReact(mode) { omiReacted(mode); }

    // The corner card's main button for the tutorial's action steps.
    readonly property string primaryText: !step ? "" : step.id === "theme" ? "Keep my theme"
                                        : step.id === "display" ? "Looks right"
                                        : step.id === "apps" ? "Continue" : ""
    readonly property bool primaryEnabled: true
    // How far through the tutorial, 0 to 1: the current tutorial step counts,
    // and the finish screen is full. -1 (no line) on the welcome page.
    readonly property real progress: {
        if (!step || !steps) return -1;
        if (step.id === Engine.FINISH) return 1;
        var tutorial = Engine.tutorialSteps(steps).map(function (s) { return s.id; });
        var i = tutorial.indexOf(step.id);
        return i < 0 ? -1 : (i + 1) / tutorial.length;
    }

    onStepChanged: stepEntered()

    // ------------------------------------------------------------ lifecycle

    function open(payloadJson) {
        var payload = {};
        try { payload = payloadJson ? JSON.parse(payloadJson) : {}; } catch (e) { payload = {}; }
        if (!payload || typeof payload !== "object") payload = {};

        error = "";
        pausing = false;
        away = "";
        preparedStep = "";
        drillWindows = {};
        statePath = payload.state ? String(payload.state) : defaultStatePath;
        recordPath = payload.record ? String(payload.record) : "";
        dryRun = !!payload.dryRun;
        factsOverride = payload.facts && typeof payload.facts === "object" ? payload.facts : {};
        confirm = null;
        updateStatus = "";
        updating = false;
        recordLines = [];
        logLines = [];
        startedAt = Date.now();
        opened = true;
        keepCornerCardOnTop();

        flow = null;
        try {
            steps = Engine.validateManifest(JSON.parse(stepsFile.text()));
        } catch (e) {
            fault(e.message);
            return "error: " + e.message;
        }
        // Load the state, then the log, then probe the facts, then begin.
        pendingPayload = payload;
        stateReader.command = [pluginDir + "/bin/onboarding-read", statePath];
        stateReader.running = true;
        return "ok";
    }

    function stateLoaded(exitCode, text) {
        // 3: no state file yet. Anything else but 0 is a failed read, and a
        // fresh state must never be saved over a file that couldn't be read.
        if (exitCode !== 0 && exitCode !== 3) {
            fault("cannot read the state file " + statePath);
            return;
        }
        try {
            flow = Engine.parseState(exitCode === 3 ? "" : text, now());
        } catch (e) {
            fault(e.message);
            return;
        }
        logReader.command = [pluginDir + "/bin/onboarding-read", logFile.path];
        logReader.running = true;
    }

    function logLoaded(exitCode, text) {
        var lines = exitCode === 0 ? String(text).split("\n").filter(function (l) { return l !== ""; }) : [];
        logLines = lines.slice(Math.max(0, lines.length - 2000));
        factsProbe.running = true;
    }

    // The corner card shares Hyprland's overlay level with Omarchy's menus,
    // whose full-screen dimming would otherwise cover it. Within a level
    // Hyprland draws higher `order` first, so a negative order keeps the card
    // on top. It's a runtime rule (a config reload clears it), so it's set on
    // every open; the name makes Hyprland reuse it rather than add another.
    function keepCornerCardOnTop() {
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "omarchy-onboarding-coach", match = { namespace = "^omarchy-onboarding-coach$" }, order = -10 })']);
    }

    // Idempotent: dismissOverlay() calls it and then shell.hide(), which calls it again.
    function close() {
        opened = false;
        pausing = false;
        away = "";
        drill = null;
        ticked = {};
        queue = [];
        doItQueue = [];
        pendingPayload = null;
    }

    function dismissOverlay() {
        close();
        if (shell && typeof shell.hide === "function") shell.hide(pluginId);
    }

    // Runs once the facts are in: start, resume, re-run or replay.
    function begin(payload) {
        var before = flow ? Object.assign({}, flow.steps) : {};
        try {
            if (payload.step) flow = Engine.replay(steps, flow, String(payload.step), now());
            else if (flow.status === "completed" || flow.status === "dismissed")
                flow = Engine.rerun(flow, !!payload.onlySkipped, now());
            else flow = Engine.start(steps, flow, facts, now());
        } catch (e) {
            fault(e.message);
            return;
        }
        log("open status=" + flow.status + " current=" + (step ? step.id : "none") + (dryRun ? " (dry run)" : ""));
        logSkips(before);
        save();
        syncDrill();
    }

    // One log line per step the rules passed over, with the reason.
    function logSkips(before) {
        Object.keys(flow.steps).forEach(function (id) {
            var r = flow.steps[id], was = before[id];
            if ((r.outcome === "auto-skipped" || r.outcome === "deferred")
                    && (!was || was.outcome !== r.outcome || was.at !== r.at))
                log("auto " + r.outcome.replace("auto-", "") + " " + id + ": " + (r.reason || ""));
        });
    }

    // ------------------------------------------------------------ flow

    function next() { return change(function () { return Engine.complete(steps, flow, facts, now()); }, "done"); }
    function skip() { return change(function () { return Engine.skip(steps, flow, facts, now()); }, "skip"); }
    function pause() { return change(function () { return Engine.pause(flow, now()); }, "pause"); }
    function dismiss() { return change(function () { return Engine.dismiss(flow, now()); }, "dismiss"); }

    // The current step's link (the manual, on the finish screen): opened as a
    // web app, the way Omarchy's menu opens it. The finish card covers the
    // screen, so it also finishes, or the page would open behind it. Opened
    // first: finishing closes the overlay, and nothing runs after that.
    function openLink() {
        var link = step && step.link;
        if (!link || !link.url) return "no link";
        log("open " + link.url);
        Quickshell.execDetached(["omarchy-launch-webapp", String(link.url)]);
        if (step.id === "finish") next();
        return "ok";
    }

    // The welcome checklist's two ways out.
    function startTutorial() { return change(function () { return Engine.complete(steps, flow, facts, now()); }, "start tutorial"); }
    function closeWelcome() { return change(function () { return Engine.finishNow(flow, now()); }, "close welcome"); }

    function askPause() {
        pausing = true;
        log("pause dialog");
    }

    function resume() {
        pausing = false;
        resetIdle();
    }

    // `info` rather than `state`, which Item already has.
    function info() {
        return JSON.stringify({
            opened: opened,
            status: flow ? flow.status : null,
            step: step ? step.id : null,
            drill: drill ? drill.step : null,
            ticked: Object.keys(ticked).filter(function (k) { return k !== "__step"; }),
            windows: drillWindows,
            centered: centered,
            away: away,
            pausing: pausing,
            hint: hint,
            confirm: confirm ? confirm.question : null,
            dryRun: dryRun,
            checklist: checklist.map(function (r) { return r.id + ":" + (r.done ? "done" : r.action || "-"); }),
            ssid: ssid,
            updateStatus: updateStatus,
            updating: updating,
            themeBaseline: themeBaseline,
            monitors: monitors,
            apps: apps.map(function (a) { return a.label; }),
            appsTried: Object.keys(appsTried),
            facts: facts,
            error: error
        });
    }

    function change(fn, label) {
        if (!flow) return "not open";
        var beforeSteps = Object.assign({}, flow.steps);
        try {
            flow = fn();
        } catch (e) {
            log(label + " refused: " + e.message);
            return e.message;
        }
        pausing = false;
        away = "";
        log(label + " -> status=" + flow.status + " current=" + (step ? step.id : "none"));
        logSkips(beforeSteps);
        save();
        markDone();
        syncDrill();
        if (!step) dismissOverlay();
        return "ok";
    }

    // The `onboarding` omarchy-done marker once finished or dismissed, only for
    // the real state file so test runs never mark the real account.
    function markDone() {
        if (statePath !== defaultStatePath || marked.onboarding) return;
        if (flow.status !== "completed" && flow.status !== "dismissed") return;
        marked = { onboarding: true };
        Quickshell.execDetached(["omarchy-done", "mark", "onboarding"]);
        log("omarchy-done mark onboarding");
    }

    // ------------------------------------------------------------ welcome checklist

    // Wi-Fi: the network panel does the work; the checklist steps aside and
    // comes back once the machine is online.
    function connect() {
        openPanel("omarchy.network");
        away = "wifi";
        return "ok";
    }

    // The one safe way to update, in a terminal. The checklist steps aside
    // until that terminal closes.
    function update() {
        if (facts.online !== true || updating) return "not now";
        askConfirm("Ready to update? Omarchy takes a snapshot first, then updates in a terminal. It may ask for your password.",
                   "Update", function () {
            updating = true;
            away = "update";
            runSystem(["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"], function (code) {
                updating = false;
                log("update terminal closed with " + code);
                if (away === "update") away = "";
                checkForUpdate();
            });
        });
        return "ok";
    }

    function checkForUpdate() {
        // Tests pin the result, e.g. {"update": "available"}.
        if (factsOverride.update) {
            updateStatus = factsOverride.update;
            return;
        }
        if (facts.online !== true || updateCheck.running) return;
        updateStatus = "checking";
        updateCheck.running = true;
    }

    function showKeybindings() {
        Quickshell.execDetached(["omarchy-menu-keybindings"]);
        away = "keys";
        log("show keybindings");
        return "ok";
    }

    // The corner card's "Back to the checklist".
    function comeBack() {
        away = "";
        resetIdle();
        return "ok";
    }

    // A checklist row's button.
    function checklistAction(id) {
        if (id === "wifi") return connect();
        if (id === "update") return updateStatus === "unknown" ? checkForUpdate() : update();
        if (id === "keys") return showKeybindings();
        return "no such row";
    }

    // ------------------------------------------------------------ do it for me

    // Runs what the step's keys would, on the drill's own windows.
    function doIt() {
        if (!step) return "not open";
        var plan = Ui.doItPlan(step.id, {
            ticked: ticked,
            windows: drillWindows,
            workspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1,
            home: drillHome
        });
        if (!plan) return "nothing to do";
        log("do it for me: " + step.id + " " + JSON.stringify(plan));
        resetIdle();
        if (plan.special === "complete") return next();
        if (plan.special === "skip") return skip();
        if (plan.special === "fill") {
            Quickshell.execDetached(["wl-copy", Ui.CLIPBOARD_SAMPLE]);
            if (coach.item && coach.item.pasteField) coach.item.pasteField.text = Ui.CLIPBOARD_SAMPLE;
            return "ok";
        }
        doItQueue = plan.run.slice();
        runDoIt();
        return "ok";
    }

    // Detached: launchers such as omarchy-launch-terminal live as long as the
    // window they open, so nothing waits for them to exit.
    function runDoIt() {
        if (!doItQueue.length || doItWait.running) return;
        var q = doItQueue.slice();
        var item = q.shift();
        doItQueue = q;
        Quickshell.execDetached(item.argv);
        doItWait.interval = Math.max(1, item.wait || 0);
        doItWait.start();
    }

    // ------------------------------------------------------------ system changes

    function askConfirm(question, confirmText, run) {
        confirm = { question: question, confirmText: confirmText, run: run };
        log("confirm? " + question);
    }

    function answerConfirm(yes) {
        var c = confirm;
        confirm = null;
        resetIdle();
        log("confirm " + (yes ? "yes" : "no"));
        if (yes && c) c.run();
    }

    // Runs a command that changes the system, or only logs it in a dry run.
    // `done(exitCode)` runs when it exits; launchers that open a terminal exit
    // when that terminal closes.
    function runSystem(argv, done) {
        if (dryRun) {
            log("dry-run: would run " + argv.join(" "));
            if (done) Qt.callLater(function () { done(0); });
            return;
        }
        log("run " + argv.join(" "));
        var proc = systemProcess.createObject(root, { command: argv, done: done || null });
        proc.running = true;
    }

    function openPanel(id) {
        Quickshell.execDetached(["omarchy-shell", "shell", "toggle", id]);
        log("open panel " + id);
    }

    // ------------------------------------------------------------ tutorial action steps

    // Apps. An app that installs on first use asks first.
    function tryApp(app) {
        if (typeof app === "string") app = apps.filter(function (a) { return a.label === app; })[0];
        if (!app) return "no such app";
        var launch = function () {
            if (app.installs && dryRun) log("dry-run: would install and open " + app.label);
            else Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.exec_cmd(" + JSON.stringify(app.command) + ")"]);
            var tried = Object.assign({}, appsTried);
            tried[app.label] = true;
            appsTried = tried;
            resetIdle();
            log("try app " + app.label);
        };
        if (app.installs)
            askConfirm(app.label + " isn't installed yet. Trying it opens a terminal that installs it first.", "Install and open", launch);
        else
            launch();
        return "ok";
    }

    function primaryAction() {
        if (step) next();
    }

    // Ticks a sub-task of a step without a drill tracker.
    function tick(id) {
        if (ticked[id]) return;
        var t = Object.assign({}, ticked);
        t[id] = true;
        ticked = t;
        resetIdle();
        log("step " + (step ? step.id : "?") + "/" + id + " ticked");
        omiReact("success");
        // A new theme: let the restyle land before moving on.
        if (step && step.id === "theme" && id === "apply") themeDone.start();
        if (step && step.id === "clipboard" && t.copy && t.paste) {
            log("drill clipboard complete");
            next();
        }
    }

    // The clipboard step's field calls this on every change.
    function pasted(text) {
        if (step && step.id === "clipboard" && String(text).indexOf(Ui.CLIPBOARD_SAMPLE) >= 0) tick("paste");
    }

    // ------------------------------------------------------------ steps and drills

    function stepEntered() {
        resetIdle();
        if (!step || step.id === preparedStep) return;
        preparedStep = step.id;
        if (step.id === "welcome") {
            checkForUpdate();
        } else if (step.id === "theme") {
            themeBaseline = "";
            themeProbe.running = true;
        } else if (step.id === "display") {
            lastScales = null;
            sunsetBaseline = "";
            sunsetSeen = false;
        } else if (step.id === "apps") {
            appsProbe.running = true;
        } else if (step.id === "clipboard" && !flow.steps.clipboard) {
            // Spec: the app opens a terminal with a sample line to copy.
            Quickshell.execDetached(["omarchy-launch-terminal", "bash", "-c",
                "printf '\\n  %s\\n\\n' '" + Ui.CLIPBOARD_SAMPLE + "'; exec bash"]);
            log("clipboard: opened a terminal with the sample line");
        }
    }

    function resetIdle() {
        lastProgress = Date.now();
        clock = lastProgress;
    }

    function syncDrill() {
        var id = step ? step.id : "";
        if (Drills.DRILL_STEPS.indexOf(id) < 0) {
            if (drill || !step || ticked.__step !== id) {
                drill = null;
                ticked = { __step: id };
            }
            return;
        }
        if (drill && drill.step === id) return;
        drill = Drills.create(id, { defaultBrowser: defaultBrowser });
        drillHome = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
        ticked = {};
        lastClients = null;
        log("drill " + id + " started");
    }

    function enqueue(obs) {
        var q = queue.slice();
        if (obs.kind === "hypr" && obs.line === "openlayer>>" + Drills.MENU_LAYER) q.push({ probe: true });
        q.push(obs);
        queue = q;
        drain();
    }

    function drain() {
        while (queue.length && !probing) {
            var q = queue.slice();
            var item = q.shift();
            queue = q;
            if (item.probe) {
                probing = true;
                keybindingsProbe.running = true;
                return;
            }
            observe(item);
        }
    }

    function observe(obs) {
        if (recordPath) {
            var line = JSON.stringify(Object.assign({ t: Math.round(Date.now() - startedAt) }, obs));
            recordLines = recordLines.concat([line]);
            recordFile.setText(recordLines.join("\n") + "\n");
        }
        if (!drill) return;
        var changes = drill.observe(obs);
        if (drill.windows) drillWindows = drill.windows();
        if (changes.length) {
            var t = Object.assign({}, ticked);
            changes.forEach(function (c) {
                if (c.ticked) t[c.subtask] = true;
                else delete t[c.subtask];
                log("drill " + drill.step + "/" + c.subtask + (c.ticked ? " ticked" : " reset"));
            });
            ticked = t;
            resetIdle();
            if (changes.some(function (c) { return c.ticked; })) omiReact("success");
        }
        if (drill.complete()) {
            log("drill " + drill.step + " complete");
            next();
        }
    }

    // ------------------------------------------------------------ files

    function save() {
        if (flow) stateFile.setText(Engine.serialize(flow));
    }

    function log(message) {
        var line = Math.floor(Date.now() / 1000) + " " + message;
        console.log("onboarding: " + message);
        var lines = logLines.concat([line]);
        if (lines.length > 2000) lines = lines.slice(lines.length - 2000);
        logLines = lines;
        logFile.setText(lines.join("\n") + "\n");
    }

    function fault(message) {
        error = message;
        log("error: " + message);
    }

    function now() {
        return Math.floor(Date.now() / 1000);
    }

    FileView {
        id: stepsFile
        path: root.pluginDir + "/steps.json"
        blockLoading: true
        watchChanges: false
    }

    // Write-only: reads go through bin/onboarding-read (see stateLoaded).
    FileView {
        id: stateFile
        path: root.statePath
        preload: false
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }

    FileView {
        id: logFile
        // The log sits next to the state file: onboarding.json -> onboarding.log.
        path: root.statePath.replace(/\.json$/, "") + ".log"
        preload: false
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }

    FileView {
        id: recordFile
        path: root.recordPath
        preload: false
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }

    // ------------------------------------------------------------ probes and timers

    Process {
        id: stateReader
        stdout: StdioCollector { id: stateText; waitForEnd: true }
        onExited: function (exitCode) { root.stateLoaded(exitCode, stateText.text); }
    }

    Process {
        id: logReader
        stdout: StdioCollector { id: logText; waitForEnd: true }
        onExited: function (exitCode) { root.logLoaded(exitCode, logText.text); }
    }

    Process {
        id: skipBinder
        onExited: function (code) {
            root.skipKey = root.skipBindWanted && code === 0 ? "Ctrl + /" : "";
            if (root.skipBindWanted && code !== 0) root.log("skip key not bound: Ctrl + / is taken");
        }
    }

    Process {
        id: factsProbe
        command: [root.pluginDir + "/bin/onboarding-facts"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = String(text || "").split("\n");
                root.facts = { online: Drills.parseConnectivity(lines[0]), missing: [] };
                root.defaultBrowser = String(lines[1] || "").trim();
                root.ssid = String(lines[2] || "").trim();
                root.barPosition = String(lines[3] || "top").trim();
                // Then check that every command a step needs exists.
                checkProbe.command = [root.pluginDir + "/bin/onboarding-check"].concat(Engine.allRequirements(root.steps));
                checkProbe.running = true;
            }
        }
    }

    Process {
        id: checkProbe
        stdout: StdioCollector {
            onStreamFinished: {
                var missing = String(text || "").split("\n").filter(function (l) { return l !== ""; });
                root.facts = Object.assign({}, root.facts, { missing: missing }, root.factsOverride);
                if (missing.length) root.log("missing commands: " + missing.join(", "));
                if (root.pendingPayload) {
                    var payload = root.pendingPayload;
                    root.pendingPayload = null;
                    root.begin(payload);
                }
            }
        }
    }

    Component {
        id: systemProcess
        Process {
            property var done: null
            onExited: function (exitCode) {
                if (done) done(exitCode);
                destroy();
            }
        }
    }

    // The checklist's Wi-Fi row, live: every 2 s on the welcome screen.
    Timer {
        interval: 2000
        repeat: true
        running: root.opened && root.step !== null && root.step.id === "welcome"
                 && root.factsOverride.online === undefined
        onTriggered: if (!connectionProbe.running) connectionProbe.running = true
    }

    Process {
        id: connectionProbe
        command: [root.pluginDir + "/bin/onboarding-facts"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = String(text || "").split("\n");
                var online = Drills.parseConnectivity(lines[0]);
                var wasOnline = root.facts.online === true;
                root.ssid = String(lines[2] || "").trim();
                if (online === root.facts.online) return;
                root.facts = Object.assign({}, root.facts, { online: online });
                root.log("connection: " + (online ? "online" + (root.ssid ? " (" + root.ssid + ")" : "") : "offline"));
                if (online && !wasOnline) {
                    if (root.away === "wifi") root.away = "";
                    root.checkForUpdate();
                }
            }
        }
    }

    // `omarchy update available` exits 0 when there is one. Network-bound.
    Process {
        id: updateCheck
        command: ["omarchy", "update", "available"]
        onExited: function (exitCode) {
            root.updateStatus = exitCode === 0 ? "available" : exitCode === 1 ? "current" : "unknown";
            root.log("update check: " + root.updateStatus);
        }
    }

    // Theme: Omarchy's picker applies the theme itself; the step sees it in
    // `omarchy theme current`.
    Timer {
        interval: 1000
        repeat: true
        running: root.opened && root.step !== null && root.step.id === "theme" && !root.ticked.apply
        onTriggered: if (!themeProbe.running) themeProbe.running = true
    }

    Process {
        id: themeProbe
        command: ["omarchy", "theme", "current"]
        stdout: StdioCollector {
            onStreamFinished: {
                var name = String(text || "").trim();
                if (!name) return;
                if (!root.themeBaseline) root.themeBaseline = name;
                else if (name !== root.themeBaseline) {
                    root.log("theme changed to " + name);
                    root.tick("apply");
                }
            }
        }
    }

    Timer {
        id: themeDone
        interval: 1200
        onTriggered: if (root.step && root.step.id === "theme") root.next()
    }

    Process {
        id: appsProbe
        command: [root.pluginDir + "/bin/onboarding-apps"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.apps = JSON.parse(text); } catch (e) { root.apps = []; }
            }
        }
    }

    // Display: the scale and night light, as Hyprland reports them.
    Timer {
        interval: 1000
        repeat: true
        running: root.opened && root.step !== null && root.step.id === "display"
        triggeredOnStart: true
        onTriggered: {
            if (!monitorsProbe.running) monitorsProbe.running = true;
            if (!sunsetProbe.running) sunsetProbe.running = true;
        }
    }

    Process {
        id: monitorsProbe
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                var list;
                try { list = JSON.parse(text); } catch (e) { return; }
                root.monitors = list.map(function (m) { return { name: m.name, width: m.width, height: m.height, scale: m.scale }; });
                var scales = root.monitors.map(function (m) { return m.scale; });
                var change = Ui.scaleChange(root.lastScales, scales);
                root.lastScales = scales;
                if (change === "up") root.tick("up");
                else if (change === "down" && root.ticked.up) root.tick("down");
            }
        }
    }

    // hyprsunset only runs once the night light has been used, so "can't
    // connect" is a reading too; any change from the first reading counts.
    Process {
        id: sunsetProbe
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                var reading = String(text || "").trim().indexOf("Couldn't") === 0 ? "off" : String(text || "").trim();
                if (!root.sunsetSeen) {
                    root.sunsetSeen = true;
                    root.sunsetBaseline = reading;
                } else if (reading !== root.sunsetBaseline) {
                    root.tick("nightlight");
                }
            }
        }
    }

    Process {
        id: keybindingsProbe
        command: [root.pluginDir + "/bin/onboarding-keybindings-open"]
        onExited: function (exitCode) {
            root.probing = false;
            root.observe({ kind: "keybindings", open: exitCode === 0 });
            root.drain();
        }
    }

    // Super + J sends no event, so the tiling drill watches window positions.
    Timer {
        interval: 400
        repeat: true
        running: root.opened && ((root.drill && root.drill.step === "tiling") || root.recordPath !== "")
        onTriggered: if (!clientsProbe.running) clientsProbe.running = true
    }

    Process {
        id: clientsProbe
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                var windows = Drills.parseClients(text);
                if (!windows || Drills.sameClients(windows, root.lastClients)) return;
                root.lastClients = windows;
                root.enqueue({ kind: "clients", windows: windows });
            }
        }
    }

    // Clipboard: the copy is seen when the sample line reaches the clipboard.
    Timer {
        interval: 800
        repeat: true
        running: root.opened && root.step !== null && root.step.id === "clipboard" && !root.ticked.copy
        onTriggered: if (!clipboardProbe.running) clipboardProbe.running = true
    }

    Process {
        id: clipboardProbe
        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            onStreamFinished: if (String(text).indexOf(Ui.CLIPBOARD_SAMPLE) >= 0) root.tick("copy")
        }
    }

    Timer {
        id: doItWait
        onTriggered: root.runDoIt()
    }

    // Drives the idle hints.
    Timer {
        interval: 1000
        repeat: true
        running: root.opened && !root.pausing
        onTriggered: root.clock = Date.now()
    }

    Connections {
        target: Hyprland
        enabled: root.opened && (root.drill !== null || root.recordPath !== "" || root.away === "keys"
                                 || (root.step !== null && root.step.id === "theme"))
        function onRawEvent(event) {
            // The theme step ticks when Omarchy's picker opens.
            if (root.step && root.step.id === "theme" && !root.drill) {
                if (String(event.name) === "openlayer" && String(event.data) === "omarchy-image-selector") root.tick("open");
                return;
            }
            // The checklist comes back when the keybindings list closes.
            if (root.away === "keys") {
                if (String(event.name) === "closelayer" && String(event.data) === Drills.MENU_LAYER) root.comeBack();
                return;
            }
            root.enqueue({ kind: "hypr", line: String(event.name) + ">>" + String(event.data) });
        }
    }

    // A config reload (a theme change does one) clears runtime layer rules
    // and binds, so both are set again.
    Connections {
        target: Hyprland
        enabled: root.opened
        function onRawEvent(event) {
            if (String(event.name) !== "configreloaded") return;
            root.keepCornerCardOnTop();
            if (root.skipBindWanted) root.setSkipBind();
        }
    }

    // ------------------------------------------------------------ view

    // Centered: takes the keyboard so it can catch Super and Esc.
    PanelWindow {
        visible: root.opened && root.flow !== null && root.centered
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-onboarding"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // Dim the desktop so the card is the one thing to look at.
        Rectangle {
            anchors.fill: parent
            color: Color.background
            opacity: 0.78
        }

        Rectangle {
            id: centerCard
            anchors.centerIn: parent
            width: centerView.implicitWidth + Style.space(56)
            height: centerView.implicitHeight + Style.space(56)
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 1
            radius: Style.cornerRadius

            ProgressLine {
                progress: root.pausing || root.confirm || root.error ? -1 : root.progress
            }

            Loader {
                id: centerView
                anchors.centerIn: parent
                width: item ? item.implicitWidth : 0
                height: item ? item.implicitHeight : 0
                focus: true
                sourceComponent: root.error ? errorView
                               : root.confirm ? confirmView
                               : root.pausing ? pauseView
                               : !root.step ? null
                               : root.step.id === "welcome" ? welcomeView
                               : root.step.id === "super-key" ? superKeyView
                               : genericView
            }
        }
    }

    // Corner: the drills, and the checklist while it has stepped aside. Leaves
    // the keyboard to Hyprland, except the clipboard step, whose field the
    // user clicks to paste into.
    PanelWindow {
        id: cornerWindow
        visible: root.opened && root.flow !== null && !root.centered && (root.step !== null || root.away !== "")
        color: "transparent"
        // Unanchored on an axis means centred on it.
        readonly property string place: root.away !== "" ? "bottom-right"
            : Ui.coachPlacement(root.step ? root.step.id : "", root.ticked, root.barPosition)
        anchors {
            top: cornerWindow.place.indexOf("top") === 0
            bottom: cornerWindow.place.indexOf("bottom") === 0
            left: /-left$/.test(cornerWindow.place)
            right: /-right$/.test(cornerWindow.place) || cornerWindow.place === "right-center"
        }
        margins { top: Style.gapsOut * 4; bottom: Style.gapsOut * 4; left: Style.gapsOut * 4; right: Style.gapsOut * 4 }
        implicitWidth: coach.item ? coach.item.implicitWidth : 1
        implicitHeight: coach.item ? coach.item.implicitHeight : 1
        // Respect the bar's reserved space, so a top card sits under it.
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-onboarding-coach"
        WlrLayershell.keyboardFocus: root.away === "" && root.step && root.step.id === "clipboard"
                                     ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Loader {
            id: coach
            anchors.fill: parent
            sourceComponent: root.away !== "" ? awayCard : coachCard
        }
    }

    Component {
        id: coachCard
        CoachCard { host: root; step: root.step; ticked: root.ticked; hint: root.hint }
    }

    Component {
        id: awayCard
        AwayCard { host: root; reason: root.away }
    }

    Component {
        id: welcomeView
        WelcomeView {
            host: root
            logoPath: (root.omarchyPath || "/usr/share/omarchy") + "/logo.svg"
            rows: root.checklist
            omiMode: Ui.welcomeOmi({ online: root.facts.online === true, update: root.updating ? "updating" : root.updateStatus })
        }
    }

    Component {
        id: superKeyView
        SuperKeyView { host: root; step: root.step; hint: root.hint }
    }

    Component {
        id: confirmView
        ConfirmView { host: root; question: root.confirm ? root.confirm.question : ""; confirmText: root.confirm ? root.confirm.confirmText : "" }
    }

    Component {
        id: pauseView
        PauseView { host: root }
    }

    Component {
        id: genericView
        StepView {
            host: root
            step: root.step
            openSteps: root.flow ? Engine.openSteps(root.steps, root.flow).map(function (s) {
                var r = root.flow.steps[s.id];
                return { title: s.title, reason: r ? r.reason : "" };
            }) : []
        }
    }

    Component {
        id: errorView
        FocusScope {
            implicitWidth: Style.space(460)
            implicitHeight: errorColumn.implicitHeight
            Keys.onEscapePressed: root.dismissOverlay()
            Component.onCompleted: Qt.callLater(function () { closeButton.forceActiveFocus(); })
            Column {
                id: errorColumn
                width: parent.width
                spacing: Style.space(12)
                Row {
                    width: parent.width
                    spacing: Style.space(10)
                    CardOmi { id: errorOmi; host: root; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        width: parent.width - errorOmi.width - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Something went wrong, and I can't start."
                        wrapMode: Text.Wrap
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.heading
                    }
                }
                Text {
                    width: parent.width
                    text: root.error
                    wrapMode: Text.Wrap
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.62)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                }
                Button { id: closeButton; anchors.right: parent.right; text: "Close"; primary: true; onClicked: root.dismissOverlay() }
            }
        }
    }
}
