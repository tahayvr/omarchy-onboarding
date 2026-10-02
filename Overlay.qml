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
// runs the current step's drill against Hyprland's events, saves every
// change, and shows the step. The logic lives in lib/; the views in ui/.
//
// Two windows, never both: a centered card that takes the keyboard (welcome,
// the Super key, the pause dialog, and the later steps), and a corner card
// for the drills that leaves the keyboard to Hyprland.
//
// Payload (summon): {"state": path, "step": id, "onlySkipped": bool, "record": path}
//   state        state file instead of ~/.local/state/omarchy/onboarding.json
//   step         replay one lesson (omarchy-onboarding --step)
//   onlySkipped  when re-running, pass over steps already done
//   record       also save every observation, for replay tests
//
// Calls (omarchy-shell shell call <id> <fn> <arg>): next, skip, pause,
// dismiss, track ("mac" or "mac:code"), doIt, info.
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
    property var facts: ({ online: null, owner_setup_deferred: null })
    property string defaultBrowser: ""
    property string error: ""
    property var pendingPayload: null

    property var drill: null
    property var ticked: ({})
    // The tiling drill's terminal and browser, kept for the later drills and
    // "Do it for me", which only ever act on these.
    property var drillWindows: ({})
    property double startedAt: 0

    // Esc or ✕ shows the pause dialog over whatever step is current.
    property bool pausing: false
    // A tip for a step the track turned into a one-liner.
    property string tip: ""
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
    readonly property var copy: step ? Engine.copyFor(step, flow.track) : null
    readonly property bool centered: pausing || error !== "" || (step !== null && Ui.isCentered(step.id))
    readonly property string progressText: {
        if (!step || !steps) return "";
        var phase = steps.phases.filter(function (p) { return p.number === step.phase; })[0];
        return "Step " + step.number + " of " + (steps.steps.length - 1) + (phase ? " · " + phase.title : "");
    }

    onStepChanged: stepEntered()

    // ------------------------------------------------------------ lifecycle

    function open(payloadJson) {
        var payload = {};
        try { payload = payloadJson ? JSON.parse(payloadJson) : {}; } catch (e) { payload = {}; }
        if (!payload || typeof payload !== "object") payload = {};

        error = "";
        pausing = false;
        tip = "";
        preparedStep = "";
        drillWindows = {};
        statePath = payload.state ? String(payload.state) : defaultStatePath;
        recordPath = payload.record ? String(payload.record) : "";
        recordLines = [];
        logLines = [];
        startedAt = Date.now();
        opened = true;

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

    // Idempotent: dismissOverlay() calls it and then shell.hide(), which calls it again.
    function close() {
        opened = false;
        pausing = false;
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
        try {
            if (payload.step) flow = Engine.replay(steps, flow, String(payload.step), now());
            else if (flow.status === "completed" || flow.status === "dismissed")
                flow = Engine.rerun(flow, !!payload.onlySkipped, now());
            else flow = Engine.start(steps, flow, facts, now());
        } catch (e) {
            fault(e.message);
            return;
        }
        log("open status=" + flow.status + " current=" + (step ? step.id : "none"));
        save();
        syncDrill();
    }

    // ------------------------------------------------------------ calls and view actions

    function next() { return change(function () { return Engine.complete(steps, flow, facts, now()); }, "done"); }
    function skip() { return change(function () { return Engine.skip(steps, flow, facts, now()); }, "skip"); }
    function pause() { return change(function () { return Engine.pause(flow, now()); }, "pause"); }
    function dismiss() { return change(function () { return Engine.dismiss(flow, now()); }, "dismiss"); }

    function track(arg) {
        var parts = String(arg || "").split(":");
        return change(function () { return Engine.chooseTrack(flow, parts[0], parts[1] === "code", now()); }, "track " + arg);
    }

    // The welcome screen's Start.
    function chooseTrack(trackId, writesCode) {
        var result = track(trackId + (writesCode ? ":code" : ""));
        return result === "ok" ? next() : result;
    }

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
            ticked: Object.keys(ticked),
            windows: drillWindows,
            centered: centered,
            pausing: pausing,
            hint: hint,
            facts: facts,
            error: error
        });
    }

    function change(fn, label) {
        if (!flow) return "not open";
        var before = flow.current;
        try {
            flow = fn();
        } catch (e) {
            log(label + " refused: " + e.message);
            return e.message;
        }
        pausing = false;
        log(label + " -> status=" + flow.status + " current=" + (step ? step.id : "none"));
        tip = tipsSince(before);
        save();
        syncDrill();
        if (!step) dismissOverlay();
        return "ok";
    }

    // Tips of the steps the track turned into one-liners since `fromId`.
    function tipsSince(fromId) {
        var from = Engine.indexOf(steps, fromId), to = step ? Engine.indexOf(steps, step.id) : -1;
        if (from < 0 || to <= from) return "";
        return steps.steps.slice(from + 1, to).filter(function (s) {
            var r = flow.steps[s.id];
            return s.tip && r && r.outcome === "auto-skipped" && /tip/.test(r.reason || "");
        }).map(function (s) { return s.tip; }).join(" ");
    }

    // "Do it for me": runs what the step's keys would, on the drill's own windows.
    function doIt() {
        if (!step) return "not open";
        var plan = Ui.doItPlan(step.id, {
            ticked: ticked,
            windows: drillWindows,
            workspace: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
        });
        if (!plan) return "nothing to do";
        log("do it for me: " + step.id + " " + JSON.stringify(plan));
        resetIdle();
        if (plan.special === "complete") return next();
        if (plan.special === "skip") return skip();
        if (plan.special === "fill") {
            Quickshell.execDetached(["wl-copy", Ui.CLIPBOARD_SAMPLE]);
            if (coach.item) coach.item.pasteField.text = Ui.CLIPBOARD_SAMPLE;
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

    // The clipboard step's field calls this on every change.
    function pasted(text) {
        if (!step || step.id !== "clipboard") return;
        if (String(text).indexOf(Ui.CLIPBOARD_SAMPLE) >= 0) tickClipboard("paste");
    }

    // ------------------------------------------------------------ steps and drills

    function stepEntered() {
        resetIdle();
        if (!step || step.id === preparedStep) return;
        preparedStep = step.id;
        if (step.id === "clipboard" && !flow.steps.clipboard) {
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
        if (id === "clipboard") {
            if (!drill || drill.step !== "clipboard") {
                drill = { step: "clipboard" };
                ticked = {};
            }
            return;
        }
        if (Drills.DRILL_STEPS.indexOf(id) < 0) {
            drill = null;
            ticked = {};
            return;
        }
        if (drill && drill.step === id) return;
        drill = Drills.create(id, { defaultBrowser: defaultBrowser });
        ticked = {};
        lastClients = null;
        log("drill " + id + " started");
    }

    function tickClipboard(id) {
        if (ticked[id]) return;
        var t = Object.assign({}, ticked);
        t[id] = true;
        ticked = t;
        resetIdle();
        log("drill clipboard/" + id + " ticked");
        if (t.copy && t.paste) {
            log("drill clipboard complete");
            next();
        }
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
        if (!drill || typeof drill.observe !== "function") return;
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

    FileView {
        id: logoFile
        path: (root.omarchyPath || "/usr/share/omarchy") + "/logo.txt"
        blockLoading: true
        watchChanges: false
        printErrors: false
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
        id: factsProbe
        command: [root.pluginDir + "/bin/onboarding-facts"]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = String(text || "").split("\n");
                root.facts = {
                    online: Drills.parseConnectivity(lines[0]),
                    owner_setup_deferred: lines[1] === "yes"
                };
                root.defaultBrowser = String(lines[2] || "").trim();
                if (root.pendingPayload) {
                    var payload = root.pendingPayload;
                    root.pendingPayload = null;
                    root.begin(payload);
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

    // Step 8: the copy is seen when the sample line reaches the clipboard.
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
            onStreamFinished: if (String(text).indexOf(Ui.CLIPBOARD_SAMPLE) >= 0) root.tickClipboard("copy")
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
        enabled: root.opened && ((root.drill !== null && typeof root.drill.observe === "function") || root.recordPath !== "")
        function onRawEvent(event) {
            root.enqueue({ kind: "hypr", line: String(event.name) + ">>" + String(event.data) });
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

            Loader {
                id: centerView
                anchors.centerIn: parent
                width: item ? item.implicitWidth : 0
                height: item ? item.implicitHeight : 0
                focus: true
                sourceComponent: root.error ? errorView
                               : root.pausing ? pauseView
                               : !root.step ? null
                               : root.step.id === "welcome" ? welcomeView
                               : root.step.id === "super-key" ? superKeyView
                               : genericView
            }
        }
    }

    // Corner: the drills. Leaves the keyboard to Hyprland, except the
    // clipboard step, whose field the user clicks to paste into.
    PanelWindow {
        visible: root.opened && root.step !== null && !root.centered
        color: "transparent"
        anchors { bottom: true; right: true }
        margins { bottom: Style.gapsOut * 4; right: Style.gapsOut * 4 }
        implicitWidth: coach.item ? coach.item.implicitWidth : 1
        implicitHeight: coach.item ? coach.item.implicitHeight : 1
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-onboarding-coach"
        WlrLayershell.keyboardFocus: root.step && root.step.id === "clipboard" ? WlrKeyboardFocus.OnDemand
                                                                             : WlrKeyboardFocus.None

        Loader {
            id: coach
            anchors.fill: parent
            sourceComponent: CoachCard {
                host: root
                step: root.copy
                ticked: root.ticked
                hint: root.hint
                tip: root.tip
            }
        }
    }

    Component {
        id: welcomeView
        WelcomeView { host: root; logoText: logoFile.text() }
    }

    Component {
        id: superKeyView
        SuperKeyView { host: root; step: root.copy; hint: root.hint }
    }

    Component {
        id: pauseView
        PauseView { host: root }
    }

    Component {
        id: genericView
        StepView {
            host: root
            step: root.copy
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
                Text {
                    text: "Onboarding can't start"
                    color: Color.foreground
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
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
