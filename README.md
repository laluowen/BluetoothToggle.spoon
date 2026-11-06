# BluetoothToggle.spoon

A simple [Hammerspoon](https://www.hammerspoon.org/) [Spoon](https://github.com/Hammerspoon/hammerspoon/blob/master/SPOONS.md) to quickly turn Bluetooth on and off on macOS using `blueutil`.

Features:
  - Toggle Bluetooth power with a hotkey (optional)
  - Menubar icon for quick access (enabled by default), using bundled Bluetooth icons when available
  - Optional on-screen alerts when toggling
  - Optional custom sounds for on/off actions
  - Reads current Bluetooth state from `blueutil` before each toggle
  - Optional periodic refresh so menubar state follows manual changes

## Requirements

- [`blueutil`](https://github.com/toy/blueutil) must be installed and available in your shell `PATH`, or configured explicitly with `blueutilPath`

### Path Resolution Notes

By default, the spoon tries to find `blueutil` in this order:

1. Explicit `blueutilPath` if it is an absolute path
2. `command -v blueutil` from Hammerspoon's shell environment
3. Common Homebrew locations (`/opt/homebrew/bin/blueutil`, `/usr/local/bin/blueutil`)

If your setup is unusual, set `blueutilPath` explicitly.

## Icon Credits

Bluetooth icons are from [Material Design Icons](https://github.com/Templarian/MaterialDesign), licensed under Apache-2.0. They are not covered by this Spoon's MIT license.

## Troubleshooting

- If menu shows `BT?` and alerts report command failure, check macOS Bluetooth permission for Hammerspoon:
  - System Settings > Privacy & Security > Bluetooth > enable Hammerspoon
  - Hammerspoon is not listed by default. Click the `+` at the bottom left of the list, pick `/Applications/Hammerspoon.app`, then enable it.
  - Quit and reopen Hammerspoon after granting.

## BluetoothToggle:configure

Configures the BluetoothToggle Spoon.

Parameters:
 * opts - A table of options:
   * `blueutilPath` (string) - Path to the `blueutil` binary (default: `"blueutil"`)
   * `enableMenubar` (boolean) - Show menubar icon (default: `true`)
   * `hotkey` (table) - Hotkey to toggle Bluetooth power (default: `nil`)
   * `enableAlert` (boolean) - Show alert when toggling (default: `false`)
   * `menuIconSize` (number, table, or `false`) - Menubar icon size in points; use a number for a square icon, `{ w = ..., h = ... }`, or `false` to auto-size from menubar height (default: `false`)
   * `menuIconTemplate` (boolean) - Render menubar icons as template images so macOS tints them to the menubar colour. Keeps the icon colour when `false` (default: `false`)
   * `alertIconSize` (number or table) - Alert icon size in points; use a number for a square icon or `{ w = ..., h = ... }` (default: `64`)
   * `sounds` (table) - Table with `off` and/or `on` sound file paths (default: `nil`)
   * `refreshInterval` (number) - Seconds between menu refreshes; set to `0` to disable (default: `5`)

Example:

```lua
hs.loadSpoon("BluetoothToggle")
spoon.BluetoothToggle:configure{
  blueutilPath = "/opt/homebrew/bin/blueutil",
  enableMenubar = true,
  hotkey = {{"ctrl", "shift"}, "B"},
  enableAlert = true,
  menuIconSize = false,
  menuIconTemplate = false,
  alertIconSize = 56,
  refreshInterval = 5,
  sounds = {
    off = "/System/Library/Sounds/Bottle.aiff",
    on = "/System/Library/Sounds/Pop.aiff"
  }
}
```

## License

MIT. See [LICENSE.md](LICENSE.md). Bundled icons are Apache-2.0, see Icon Credits.
