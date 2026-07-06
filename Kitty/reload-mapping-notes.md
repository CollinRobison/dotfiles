# Kitty Reload Mapping Notes

## Goal

Map the reload-config action to `ctrl+cmd+,` and have kitty's command palette reflect the mapping correctly, while keeping reload behavior from resetting the active theme/settings.

## Environment

- kitty version: `0.47.4`
- Active config reported by `debug_config`: `/Users/collinrobison/.config/kitty/kitty.conf`
- Symlink: `~/.config/kitty/kitty.conf -> /Users/collinrobison/Repos/dotfiles/Kitty/kitty.conf`
- Symlink: `~/.config/kitty/current-theme.conf -> /Users/collinrobison/Repos/dotfiles/Kitty/current-theme.conf`

## Attempts And Results

### `map ctrl+cmd+r load_config_file`

- Result: did not show as expected in command palette.
- Palette continued to show default reload entries such as `ctrl+cmd+,` and `kitty_mod+f5`.

### Unmap defaults, then map `ctrl+cmd+r`

```conf
map ctrl+cmd+,
map kitty_mod+f5
map ctrl+cmd+r load_config_file
```

- Result: command palette showed `load_config_file` as `(unmapped)`.

### `map ctrl+cmd+, load_config_file`

```conf
map kitty_mod+f5
map ctrl+cmd+, load_config_file
```

- Result from `debug_config`: kitty accepted the binding, but reported it as `ctrl+cmd+, -> reload_config`.
- User result: keybind/command palette behavior still considered not working for the intended `load_config_file` search/display.
- Important: `reload_config` is an internal/debug name, not a valid mappable action in `kitty.conf`.

### `map ctrl+cmd+comma load_config_file`

```conf
map kitty_mod+f5
map ctrl+cmd+comma load_config_file
```

- Result: command palette still showed `load_config_file` as `(unmapped)`.
- Likely not the correct spelling for this key in user mappings; docs/default display use literal comma.

### Explicit absolute path

```conf
map ctrl+cmd+, load_config_file /Users/collinrobison/Repos/dotfiles/Kitty/kitty.conf
```

- Result: command palette showed the mapping more like expected.
- Problem: pressing the keybind reset visual/theme settings toward defaults.
- Likely cause: explicit `load_config_file <path>` replaces current config state rather than performing the safe no-argument reload behavior.

### Explicit `~/.config` path

```conf
map ctrl+cmd+, load_config_file ~/.config/kitty/kitty.conf
```

- Result: command palette showed the mapping more like expected.
- Problem: pressing the keybind reset visual/theme settings toward defaults.
- Possible issue: `~` expansion in action argument may not behave like normal config-file path resolution, but the reset persisted with other explicit path forms too.

### Explicit `${HOME}` path

```conf
map ctrl+cmd+, load_config_file ${HOME}/.config/kitty/kitty.conf
```

- Result: still reset visual/theme settings toward defaults when triggered.

### Explicit relative path

```conf
map ctrl+cmd+, load_config_file kitty.conf
```

- Result: still reset visual/theme settings toward defaults when triggered.

### Typo encountered

```conf
map ctrl+cmd+, load_config_files
```

- Result: invalid action because kitty's action is singular: `load_config_file`.

### Invalid mappable action tried

```conf
map ctrl+cmd+, reload_config
```

- Result: invalid; `reload_config` appears in debug output but is not a real user-facing mappable action.

## Current Understanding

- `load_config_file` with no path is the real safe mappable action.
- kitty `debug_config` normalizes the no-path reload binding to `reload_config` internally.
- On macOS, kitty promotes `load_config_file` shortcuts into Cocoa/global menu shortcuts and names them `reload_config` internally. `reload_config` is not a public mappable action and does not appear in command palette search.
- This can make `load_config_file` appear unmapped in the command palette after removing the non-global `kitty_mod+f5` binding, even though `ctrl+cmd+,` is active as a macOS/global shortcut.
- Explicit `load_config_file <path>` makes command palette/search display closer to the desired raw `load_config_file` action, but changes behavior and causes settings/theme reset in this setup.
- The current unresolved issue: user reports the safe no-path mapping still does not work as desired, even though `debug_config` showed kitty accepted it as `ctrl+cmd+, -> reload_config`.

### Workaround being tested: wrap in `combine`

```conf
map ctrl+cmd+, combine : load_config_file : show_error Reloaded kitty.conf
```

- Hypothesis: wrapping the action in `combine` may prevent kitty's macOS global-shortcut promotion from recognizing it as the special `load_config_file` action, keeping it in the normal keymap and therefore visible in the command palette.
- Expected behavior if successful: command palette should show the key mapped to a `combine` action, pressing the key should run safe no-path `load_config_file` without resetting settings, then show a visible `Reloaded kitty.conf` overlay.
- Needs user test after full restart/reload.

### `ctrl+cmd+d debug_config`

- Result: command palette showed the mapping, but pressing the key did not open debug config.
- Likely cause: macOS intercepts `ctrl+cmd+d` for Look Up/Dictionary before kitty receives it.
- Changed to `ctrl+cmd+shift+d debug_config`.

## Current Tail Of Config Should Be Checked Before Further Changes

Expected safe baseline:

```conf
map kitty_mod+f5
map ctrl+cmd+, combine : load_config_file : show_error Reloaded kitty.conf
map ctrl+cmd+shift+d debug_config
```
