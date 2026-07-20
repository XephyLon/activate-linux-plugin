# Activate Linux — end4-pC plugin

A minimal [end4-pC](https://github.com/XephyLon/end4-pC) package plugin that toggles an
"Activate Linux" watermark from the shell's settings. It does not draw the watermark itself — it
manages the external [`activate-linux`](https://github.com/MrGlockenspiel/activate-linux) binary,
which renders its own overlay.

This repo doubles as a fixture for the shell's remote plugin install path (manifest import +
download), so everything is served from one HTTPS origin.

## Requirements

- The `activate-linux` binary on `PATH` (Arch: `activate-linux` in the AUR).
- end4-pC with plugin support.

## Install

In the shell's **Settings → Plugins**, paste the manifest URL:

```
https://raw.githubusercontent.com/XephyLon/activate-linux-plugin/main/manifest.json
```

The installer downloads the manifest and the files listed in `package.files` into
`~/.config/illogical-impulse/plugins/activate_linux/`. Enable the plugin, then flip **Show
watermark** in its settings.

All URLs resolve to `raw.githubusercontent.com`, satisfying the installer's same-origin rule.

## How it works

- `manifest.json` declares an invisible `desktopWidget` entry point. It is the only always-alive
  QML context for a settings-only plugin, so it hosts the process while rendering nothing.
- `ActivateLinuxHost.qml` launches `activate-linux` in the foreground (no `-d`), so toggling the
  option off or disabling the plugin tears the watermark down with it. Flag changes relaunch it,
  debounced. A near-instant exit (missing binary, bad args) is reported once and not retried.

## Options

| Option | activate-linux flag |
|--------|---------------------|
| Show watermark | (enables the process) |
| Title | `-t` |
| Message | `-m` |
| Color (r-g-b-a, 0.0-1.0) | `-c` |
| Bold text | `-b` |
| Scale | `-s` |

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
