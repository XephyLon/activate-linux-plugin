pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.modules.common.plugins

// Invisible desktop-widget host. A settings-only plugin persists options but
// runs no QML, so there is nothing to launch the watermark. The desktop entry
// point is the one context that stays alive for as long as the plugin is
// enabled, so it owns the activate-linux process while drawing nothing itself
// (zero implicit size -> PluginWidget allocates no blur surface or texture).
Item {
    id: root
    visible: false
    implicitWidth: 0
    implicitHeight: 0

    // Docker's package widget hardcodes its own manifest id the same way; the
    // component is not told its id, and PluginState is keyed by it.
    readonly property string pluginId: "activate_linux"

    readonly property bool watermarkEnabled: PluginState.option(pluginId, "enabled", false)
    readonly property string title: PluginState.option(pluginId, "title", "Activate Linux")
    readonly property string message: PluginState.option(pluginId, "message", "Go to Settings to activate Linux.")
    readonly property string color: PluginState.option(pluginId, "color", "0.35-0.35-0.35-1")
    readonly property bool bold: PluginState.option(pluginId, "bold", false)
    readonly property real scale: PluginState.option(pluginId, "scale", 1)
    // Explicit font: the binary defaults to the generic "sans" alias, which on
    // systems with Arabic (or other non-Latin) fonts installed can resolve to a
    // face with no Latin glyphs -> the whole watermark renders as tofu boxes.
    // Naming a real Latin family sidesteps the broken generic mapping.
    readonly property string font: PluginState.option(pluginId, "font", "Rubik")

    // The argv the process is currently running with, as a JSON string, or ""
    // when it should be stopped. Comparing against the desired value keeps a
    // no-op change from needlessly restarting a healthy watermark.
    property string activeKey: ""
    // A relaunch requested while the old process is still shutting down. The
    // exit handler picks it up so we never set running true and false in the
    // same tick.
    property var pendingCommand: null
    // Set immediately before we stop the process ourselves, so its exit is not
    // mistaken for a crash.
    property bool intentionalStop: false

    function desiredCommand() {
        if (!root.watermarkEnabled)
            return null;
        // Foreground (no -d): Quickshell owns the child, so toggling off or
        // unloading the plugin tears the watermark down with it. -q silences
        // the binary's console output.
        const args = ["activate-linux", "-q",
            "-t", root.title,
            "-m", root.message,
            "-c", root.color,
            "-f", root.font,
            "-s", String(root.scale)];
        if (root.bold)
            args.push("-b");
        return args;
    }

    function apply() {
        const command = root.desiredCommand();
        const key = command ? JSON.stringify(command) : "";
        // Already in the wanted state: stopped and should stay stopped, or
        // running the exact same command.
        if (key === root.activeKey && (key === "" || watermark.running))
            return;
        if (watermark.running) {
            // A running watermark cannot be reconfigured in place. Stop it and
            // let onExited launch whatever is wanted next (possibly nothing).
            root.pendingCommand = command;
            root.activeKey = key;
            root.intentionalStop = true;
            watermark.running = false;
            return;
        }
        root.launch(command, key);
    }

    function launch(command, key) {
        root.activeKey = key;
        if (!command)
            return;
        watermark.command = command;
        root.intentionalStop = false;
        watermark.running = true;
    }

    // Every option feeds one debounced apply(), so the burst of binding updates
    // as PluginState settles at startup collapses into a single launch instead
    // of a launch-kill-launch thrash.
    onWatermarkEnabledChanged: applyDebounce.restart()
    onTitleChanged: applyDebounce.restart()
    onMessageChanged: applyDebounce.restart()
    onColorChanged: applyDebounce.restart()
    onFontChanged: applyDebounce.restart()
    onBoldChanged: applyDebounce.restart()
    onScaleChanged: applyDebounce.restart()

    // Reap any orphaned watermark(s) before launching ours. A hard shell kill
    // (e.g. `killall qs`) skips Component.onDestruction, so the foreground child
    // survives and reparents to init; the next shell start then spawns another,
    // and they pile up. Reaping strays first guarantees at most one instance,
    // however the previous shell died. (apply() runs when the reap finishes.)
    Component.onCompleted: strayReaper.running = true
    Process {
        id: strayReaper
        command: ["pkill", "-x", "activate-linux"]
        onExited: applyDebounce.restart()
    }
    // Plugin disabled or shell reloading: kill the child rather than orphan it.
    Component.onDestruction: {
        root.intentionalStop = true;
        watermark.running = false;
    }

    Timer {
        id: applyDebounce
        interval: 250
        onTriggered: root.apply()
    }

    Process {
        id: watermark
        // process-lifecycle: restart-safe -- launched only from the debounced
        // apply(), never bound directly to a reactive boolean. onExited relaunches
        // solely for an explicit reconfigure, and a genuine early exit reports
        // once without retrying, so a missing binary cannot become a respawn loop.
        property double startedAt: 0
        onRunningChanged: if (running) startedAt = Date.now()
        onExited: (code, status) => {
            const wasIntentional = root.intentionalStop;
            root.intentionalStop = false;

            if (root.pendingCommand !== null) {
                // A reconfigure was waiting on this shutdown.
                const next = root.pendingCommand;
                root.pendingCommand = null;
                root.launch(next, next ? JSON.stringify(next) : "");
                return;
            }
            if (wasIntentional)
                return;
            // Exited on its own while still wanted. A near-instant exit means
            // the binary is missing or rejected its arguments; report once and
            // stay down instead of hammering.
            root.activeKey = "";
            if (root.watermarkEnabled && Date.now() - startedAt < 1500)
                console.warn(`[activate_linux] activate-linux exited early (code ${code}); is the package installed?`);
        }
    }
}
