# Omarclip

Instant replay for [Omarchy](https://omarchy.org), the Linux take on NVIDIA
ShadowPlay's <kbd>Alt</kbd>+<kbd>F10</kbd>. Omarclip keeps the last minutes of
your screen in a buffer. When something worth keeping happens, press the
hotkey and that stretch is saved as a clip, counted back from the moment you
pressed it.

It is an Omarchy shell plugin, not a separate app. Its settings are an overlay
drawn with the shell's own components, so they follow your theme. Recording
runs on the GPU encoder through
[gpu-screen-recorder](https://git.dec05eba.com/gpu-screen-recorder/about/),
the same recorder Omarchy uses for screen recording.

- **Save what just happened:** <kbd>Alt</kbd>+<kbd>F10</kbd> saves the last
  15 seconds to 20 minutes, whichever length you pick.
- **Quality like ShadowPlay's:** pick the Low, Medium or High preset, or set
  resolution, frame rate, bitrate and encoder (H.264, HEVC, AV1) yourself.
  What you choose is exactly what gets recorded, so it sets how the clip
  looks and how big it is.
- **Customizable hotkeys:** save, turn instant replay on/off, and open the
  settings. They are global Hyprland binds and work in fullscreen games.
- **Clips are filed by app.** Each clip goes to
  `~/Videos/Clips/<App>/<App> <date> <time>.mp4`, named after the window in
  focus when you pressed the key. Steam games get their own names.
- **Notifications with a preview.** Click one to watch the clip.
- **System audio and microphone**, either mixed or on separate tracks.
- **Stays out of Omarchy's way.** Omarchy's own screen recording (and its bar
  indicator) does not notice the buffer, and the buffer does not notice
  Omarchy's recordings.

## Requirements

Everything here ships with Omarchy 4; there is nothing to install.

- **Omarchy 4**, whose shell (`omarchy-shell`, Quickshell) hosts the plugin
- **gpu-screen-recorder** with `gsr-cli` (in Omarchy's base packages)
- **Hyprland**, for the global hotkeys, and `xkbcli` (libxkbcommon, which Hyprland
  depends on) to read the keymap when checking hotkeys against your own binds
- `bash`, `jq`, `ffmpeg` (for the notification preview) and the usual coreutils
- A GPU with a hardware video encoder: NVIDIA (NVENC), AMD or Intel (VA-API)

## Install

```bash
omarchy plugin add https://github.com/gelzinn/omarclip.git --enable
```

Or from a local checkout:

```bash
ln -s ~/path/to/omarclip ~/.config/omarchy/plugins/io.github.gelzinn.omarclip
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.gelzinn.omarclip
```

A camera icon appears in the bar. Instant replay starts right away.

## Using it

| Default | Does |
| --- | --- |
| <kbd>Alt</kbd>+<kbd>F10</kbd> | Save a clip of the last *replay length* |
| <kbd>Alt</kbd>+<kbd>Shift</kbd>+<kbd>F10</kbd> | Turn instant replay on or off |
| <kbd>Alt</kbd>+<kbd>Z</kbd> | Open Omarclip's settings |

You can change or clear all three in the settings. F-keys, PgUp, PgDn, Home,
End, Insert and Print work on their own; keys that type need Super, Ctrl or
Alt, and Enter, Esc, Tab, Backspace, Delete and the arrows need some
modifier. A key Hyprland already uses
is refused, and the panel tells you which bind has it. That includes a bind
you wrote by key name (`ALT, F10`) for a key Omarclip binds by keycode, and the
default hotkeys too: one already taken stays unbound. Omarclip never
overrides your binds. Its own binds live in
`~/.local/state/omarchy/toggles/hypr/omarclip.lua`, a folder Omarchy loads on
every Hyprland reload, so your config files are never touched.

The bar button opens the settings. Right-click it to save a clip, or
middle-click to turn instant replay on or off. The icon dims while the
buffer is off and flashes when a clip is saved.

### The settings panel

| Key | Does |
| --- | --- |
| <kbd>↑</kbd> <kbd>↓</kbd> | Move between settings |
| <kbd>←</kbd> <kbd>→</kbd> | Change the value |
| <kbd>Enter</kbd> | Toggle, change a hotkey, open the folder |
| <kbd>Del</kbd> | Clear a hotkey |
| <kbd>Ctrl</kbd>+<kbd>S</kbd> | Save a clip now |
| <kbd>Ctrl</kbd>+<kbd>O</kbd> | Open the clips folder |
| <kbd>Esc</kbd> | Close |

### Quality

| Preset | Resolution | Frame rate | Bitrate |
| --- | --- | --- | --- |
| Low | 720p | 30 fps | Auto |
| Medium | 1080p | 60 fps | Auto |
| High (default) | Native | 60 fps | Auto |
| Custom | any | 30, 60, 120, 144 fps | Auto, or 5–150 Mbps |

Change resolution, frame rate or bitrate and the preset becomes Custom, just
like in the NVIDIA app. A resolution above your monitor's records at the
monitor's own resolution, since clips are scaled down but never up.

**Auto** bitrate follows resolution, frame rate and encoder, at the same
sharpness for all of them: about 25 Mbps for 1080p at 60 fps in H.264, 44 Mbps
for 1440p60, 106 Mbps for 1440p at 144 fps, 6 Mbps for 720p30. HEVC and AV1
need about 30% and 40% less. Move the slider (or use ←→) to set your own;
<kbd>Enter</kbd> or <kbd>Del</kbd> on the bitrate goes back to Auto.

The buffer is recorded at a constant bitrate, so a clip's size is exactly
*bitrate × length*, and the panel shows it. One minute at 25 Mbps is about
190 MB of RAM, and 20 minutes at 50 Mbps about 7.5 GB. For long replays, lower
the bitrate or keep the buffer on disk instead (*Keep the buffer in*).

Changing quality, length, monitor or audio restarts the buffer, which empties
it. NVIDIA's instant replay does the same.

### From scripts

The shell exposes Omarclip over IPC:

```bash
omarchy-shell omarclip save        # save the replay length
omarchy-shell omarclip save 30     # save only the last 30 seconds
omarchy-shell omarclip toggle      # instant replay on/off
omarchy-shell omarclip start       # or stop
omarchy-shell omarclip panel       # open/close the settings
omarchy-shell omarclip folder      # open the clips folder
omarchy-shell omarclip status      # JSON: state, quality, buffer size, last clip
```

## Settings file

Changes save as you go to `~/.config/omarclip/config.json`. You can also edit
it by hand, and the shell picks edits up live:

```json
{
  "version": 1,
  "enabled": true,
  "length": 60,
  "preset": "high",
  "resolution": "native",
  "fps": 60,
  "bitrate": "auto",
  "codec": "h264",
  "monitor": "focused",
  "cursor": true,
  "systemAudio": true,
  "microphone": false,
  "separateTracks": true,
  "folder": "~/Videos/Clips",
  "organizeByApp": true,
  "storage": "ram",
  "notify": true,
  "hotkeys": {
    "save": { "keys": "ALT + code:76", "label": "Alt+F10" },
    "toggle": { "keys": "ALT + SHIFT + code:76", "label": "Alt+Shift+F10" },
    "open": { "keys": "ALT + code:52", "label": "Alt+Z" }
  }
}
```

If the file cannot be read or is not a valid JSON object when the shell starts,
Omarclip starts with replay, system audio and the microphone off and does not
write to the file. Your settings take effect again once the file is fixed.

| Key | |
| --- | --- |
| `enabled` | Keep the replay buffer running |
| `length` | Seconds a clip goes back, 15–1200 |
| `preset` | `low`, `medium`, `high` or `custom`. A named preset sets the three below |
| `resolution` | `"native"` or an output height: 2160, 1440, 1080, 900, 720, 480, 360 |
| `fps` | 30, 60, 120 or 144 |
| `bitrate` | `"auto"`, or the video bitrate in Mbps, 5–150 |
| `codec` | `h264`, `hevc` or `av1` |
| `monitor` | `focused` (the monitor in focus when the buffer starts) or a name like `DP-1` |
| `cursor` | Record the mouse cursor |
| `systemAudio`, `microphone` | Record your default output and default input |
| `separateTracks` | Microphone on its own audio track |
| `folder` | Where clips go |
| `organizeByApp` | A subfolder per app |
| `storage` | `ram` or `disk`, where the buffer lives |
| `notify` | Notify when a clip is saved |

The file must stay valid JSON. If it stops parsing, Omarclip keeps the last
good settings and writes nothing to it until it parses again.

## How it works

`bin/omarclip-recorder` runs `gpu-screen-recorder` in replay mode
(`-r <length>`) at constant bitrate, with an IPC socket in
`$XDG_RUNTIME_DIR/omarclip`. Saving a clip is a `save-replay <seconds>` request
on that socket. The recorder writes the file without stopping, so you can
save again right away, and clips saved close together overlap like they do in
ShadowPlay.

The recorder runs from a private copy of the binary named `omarclip-gsr`, kept
in `~/.cache/omarclip/bin` and refreshed whenever the installed recorder
changes. Omarchy's screen recording treats *any* `gpu-screen-recorder` you run
as a recording in progress. Without the copy, its record key would stop the
replay buffer instead of starting a recording, and the bar would always show
a recording.

When the screens go to sleep or a monitor is unplugged there is nothing to
record. Omarclip waits and starts the buffer again as soon as a screen is
back. Other failures retry with a growing delay and are reported once.

## Troubleshooting

**A hotkey does nothing.** `hyprctl globalshortcuts` should list
`omarclip:save`, and the settings show when another bind took the key.

**The buffer keeps stopping.** Check the shell's log:

```bash
qs log -p "$OMARCHY_PATH/shell" | grep omarclip
```

and try the recorder by hand:
`gpu-screen-recorder -w DP-1 -r 30 -bm cbr -q 50000 -o /tmp`.

**AV1 or HEVC fails to start.** Not every GPU encodes them. Pick H.264.

## Updating

```bash
omarchy plugin update io.github.gelzinn.omarclip
omarchy restart shell
```

## Uninstall

```bash
omarchy plugin remove io.github.gelzinn.omarclip
```

This stops the buffer and removes the hotkeys. Only keys Hyprland shows
bound to Omarclip and to nothing else are unbound, so a shortcut of yours on
the same keys stays. Settings stay in `~/.config/omarclip`, and your clips
stay where they are.

## Development

```bash
dev/run              # run Omarclip in its own Quickshell instance
dev/run call panel   # its IPC: open the panel there
dev/run press Down   # a key press for the panel
dev/run inspect      # panel and buffer state
dev/run log          # follow its log
dev/run down
node --test tests/   # unit tests for the logic in lib/
```

The dev instance records with its own socket, opens the panel on the monitor
you are not using without taking the keyboard, and leaves hotkeys off, so it
never fights an installed Omarclip. `OMARCLIP_DEV_FOCUS=1` and
`OMARCLIP_DEV_HOTKEYS=1` turn those back on.

| | |
| --- | --- |
| `Service.qml` | Replay buffer, saving, hotkeys, IPC |
| `Panel.qml` | The settings overlay |
| `BarWidget.qml` | The bar button |
| `components/` | Settings rows, hotkey recorder |
| `lib/` | Pure logic: config and presets, recorder arguments, hotkeys (tested with node) |
| `bin/omarclip-recorder` | Starts the replay buffer from its private copy |
| `bin/omarclip-save` | Saves the last N seconds and reads the window in focus |
| `bin/omarclip-file` | Files the clip under its app and makes the preview |
| `bin/omarclip-hotkeys` | Writes the hotkeys file and has Hyprland load it |

## License

MIT
