import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "lib/Engine.js" as Engine
import "lib/Drills.js" as Drills

// The onboarding overlay. It owns the flow while open: loads the state file,
// runs the current step's drill against Hyprland's events, and saves every
// change. The logic lives in lib/; this file wires it to the desktop.
//
// Payload (summon): {"state": path, "step": id, "onlySkipped": bool, "record": path}
//   state        state file instead of ~/.local/state/omarchy/onboarding.json
//   step         replay one lesson (omarchy-onboarding --step)
//   onlySkipped  when re-running, pass over steps already done
//   record       also save every observation, for replay tests
//
// Calls (omarchy-shell shell call <id> <fn> <arg>): next, skip, pause,
// dismiss, track ("mac" or "mac:code"), info.
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
    property double startedAt: 0

    // Observations wait here while the keybindings probe runs, so the
    // probe's answer reaches the drills before the layer event it belongs to.
    property var queue: []
    property bool probing: false
    property var lastClients: null

    property string recordPath: ""
    property var recordLines: []
    property var logLines: []

    readonly property var step: flow && steps ? Engine.currentStep(steps, flow) : null

    // ------------------------------------------------------------ lifecycle

    function open(payloadJson) {
        var payload = {};
        try { payload = payloadJson ? JSON.parse(payloadJson) : {}; } catch (e) { payload = {}; }
        if (!payload || typeof payload !== "object") payload = {};

        error = "";
        statePath = payload.state ? String(payload.state) : defaultStatePath;
        recordPath = payload.record ? String(payload.record) : "";
        recordLines = [];
        logLines = [];
        startedAt = Date.now();
        opened = true;

        try {
            steps = Engine.validateManifest(JSON.parse(stepsFile.text()));
            flow = Engine.parseState(stateFile.text(), now());
        } catch (e) {
            fault(e.message);
            return "error: " + e.message;
        }
        pendingPayload = payload;
        factsProbe.running = true;
        return "ok";
    }

    // Idempotent: dismiss() calls it and then shell.hide(), which calls it again.
    function close() {
        opened = false;
        drill = null;
        ticked = {};
        queue = [];
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

    // ------------------------------------------------------------ calls

    function next() { return change(function () { return Engine.complete(steps, flow, facts, now()); }, "done"); }
    function skip() { return change(function () { return Engine.skip(steps, flow, facts, now()); }, "skip"); }
    function pause() { return change(function () { return Engine.pause(flow, now()); }, "pause"); }
    function dismiss() { return change(function () { return Engine.dismiss(flow, now()); }, "dismiss"); }

    function track(arg) {
        var parts = String(arg || "").split(":");
        return change(function () { return Engine.chooseTrack(flow, parts[0], parts[1] === "code", now()); }, "track " + arg);
    }

    // `info` rather than `state`, which Item already has.
    function info() {
        return JSON.stringify({
            opened: opened,
            status: flow ? flow.status : null,
            step: step ? step.id : null,
            drill: drill ? drill.step : null,
            ticked: Object.keys(ticked),
            facts: facts,
            error: error
        });
    }

    function change(fn, label) {
        if (!flow) return "not open";
        try {
            flow = fn();
        } catch (e) {
            log(label + " refused: " + e.message);
            return e.message;
        }
        log(label + " -> status=" + flow.status + " current=" + (step ? step.id : "none"));
        save();
        syncDrill();
        if (!step) dismissOverlay();
        return "ok";
    }

    // ------------------------------------------------------------ drills

    function syncDrill() {
        var id = step ? step.id : "";
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
        if (changes.length) {
            var t = Object.assign({}, ticked);
            changes.forEach(function (c) {
                if (c.ticked) t[c.subtask] = true;
                else delete t[c.subtask];
                log("drill " + drill.step + "/" + c.subtask + (c.ticked ? " ticked" : " reset"));
            });
            ticked = t;
        }
        if (drill.complete()) {
            log("drill " + drill.step + " complete");
            next();
        }
    }

    // ------------------------------------------------------------ files

    function save() {
        stateFile.setText(Engine.serialize(flow));
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
        id: stateFile
        path: root.statePath
        blockLoading: true
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }

    FileView {
        id: logFile
        // The log sits next to the state file: onboarding.json -> onboarding.log.
        path: root.statePath.replace(/\.json$/, "") + ".log"
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }

    FileView {
        id: recordFile
        path: root.recordPath
        atomicWrites: true
        watchChanges: false
        printErrors: false
    }

    // ------------------------------------------------------------ probes

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

    Connections {
        target: Hyprland
        enabled: root.opened && (root.drill !== null || root.recordPath !== "")
        function onRawEvent(event) {
            root.enqueue({ kind: "hypr", line: String(event.name) + ">>" + String(event.data) });
        }
    }

    // ------------------------------------------------------------ view

    // A plain card for now; the real overlay UI is milestone M3.
    PanelWindow {
        visible: root.opened
        color: "transparent"
        anchors { top: true; right: true }
        margins { top: Style.gapsOut * 4; right: Style.gapsOut * 4 }
        implicitWidth: Style.space(360)
        implicitHeight: card.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omarchy-onboarding"
        // Never take the keyboard: Super bindings must reach Hyprland.
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        Rectangle {
            id: card
            anchors.fill: parent
            implicitHeight: content.implicitHeight + Style.space(32)
            color: Color.popups.background
            border.color: Color.popups.border
            border.width: 1
            radius: Style.cornerRadius

            Column {
                id: content
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Style.space(16) }
                spacing: Style.space(8)

                Text {
                    text: root.error ? "Onboarding error"
                        : root.step ? "Step " + root.step.number + " of " + (root.steps.steps.length - 1)
                        : "Onboarding"
                    color: Color.muted
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
                Text {
                    width: parent.width
                    text: root.error || (root.step ? root.step.title : "Starting…")
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.heading
                    wrapMode: Text.Wrap
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.step && !root.error ? (root.step.screen || root.step.goal || "") : ""
                    color: Color.popups.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.Wrap
                }
                Repeater {
                    model: root.step && root.step.subtasks ? root.step.subtasks : []
                    delegate: Text {
                        required property var modelData
                        width: parent ? parent.width : 0
                        text: (root.ticked[modelData.id] ? "✓  " : "○  ") + modelData.label
                        color: root.ticked[modelData.id] ? Color.accent : Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
}
