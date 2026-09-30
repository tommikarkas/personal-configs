# firstmate helpers

Personal helpers for running firstmate in herdr. They are symlinked into place:

| File | Linked from | What it does |
|---|---|---|
| `firstmate` | `~/.local/bin/firstmate` | Starts or reattaches the herdr `default` session with the first mate running. `firstmate --no-attach` does the same without attaching. |
| `pr-panel.sh` | `<firstmate home>/data/pr-panel.sh` | Live list of your PRs in one GitHub organisation with review state, plus merged PRs until 24h after their production deploy. |
| `prod-health-panel.sh` | `<firstmate home>/data/prod-health-panel/prod-health-panel.sh` | Live production health of configured ECS services from CloudWatch, read with an AWS SSO profile. |

Both panels redraw every 60 seconds. In a focused panel pane, press `r` (or Enter) to refresh now; resizing the pane redraws at the new size.

## Settings

Organisation, accounts and services are not in this repo. Copy `panels.conf.example` to `~/.config/firstmate/panels.conf`, `chmod 600` it, and fill it in. Set `FIRSTMATE_PANELS_CONFIG` to use another path.

## Linking after a fresh clone

```sh
ln -sf "$PWD/firstmate/firstmate" ~/.local/bin/firstmate
ln -sf "$PWD/firstmate/pr-panel.sh" "$FM_HOME/data/pr-panel.sh"
ln -sf "$PWD/firstmate/prod-health-panel.sh" "$FM_HOME/data/prod-health-panel/prod-health-panel.sh"
```
