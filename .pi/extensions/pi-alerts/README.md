# Pi alerts

Project-local Pi notifications for completion, terminal errors, permission prompts, and questions.

The extension is disabled when `pi-alerts.json` is absent or has `enabled: false`.
The dotfiles installer links the checked-in config into `~/.pi/agent/pi-alerts.json`.

```text
/pi-alerts status
/pi-alerts test
/pi-alerts test error
```

macOS backend priority:

1. `alerter` (installed by `.pi/install.sh` when Homebrew is available)
2. `terminal-notifier`
3. built-in `osascript`

The extension suppresses alerts when the detected terminal application is frontmost.
Focus detection fails open. Edit `pi-alerts.json` to change event channels, set per-event macOS `soundName` values (for example `Glass`, `Basso`, `Sosumi`, or `Pop`), or enable debug logging.

## Question alerts

The separate `.pi/extensions/pi-questionnaire.ts` extension provides the `question` and `questionnaire` tools. This alerts extension watches those tool names and sends the configured question notification while the questionnaire extension owns the interaction UI.
