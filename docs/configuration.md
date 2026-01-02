# Configuration

All configuration lives under `programs.clawdis`.

## Core

- `programs.clawdis.enable` (bool) — enable Clawdis
- `programs.clawdis.package` (package) — override package
- `programs.clawdis.stateDir` (string) — state directory (default: `~/.clawdis`)
- `programs.clawdis.workspaceDir` (string) — workspace directory
- `programs.clawdis.launchd.enable` (bool) — run gateway via launchd (macOS)

## Defaults (sensible v1)

- Providers disabled unless explicitly enabled
- Telegram group mentions not required (`requireMention = false`)
- Queue mode `interrupt` (fast replies)
- `routing.queue.bySurface` defaults to Telegram/WhatsApp interrupt, Discord/WebChat queue
- `allowFrom` required when Telegram is enabled

## Telegram (v1)

- `programs.clawdis.providers.telegram.enable` (bool)
- `programs.clawdis.providers.telegram.botTokenFile` (string)
- `programs.clawdis.providers.telegram.allowFrom` (list of int chat IDs)
- `programs.clawdis.providers.telegram.requireMention` (bool, default false)

## Routing

- `programs.clawdis.routing.queue.mode` — `queue` or `interrupt` (default: `interrupt`)
- `programs.clawdis.routing.queue.bySurface` — per-surface overrides
- `programs.clawdis.routing.groupChat.requireMention` — group activation default

## Example

```nix
{
  programs.clawdis = {
    enable = true;
    providers.telegram = {
      enable = true;
      botTokenFile = "/run/agenix/telegram-bot-token";
      allowFrom = [ 12345678 -1001234567890 ];
    };
    routing.queue.mode = "interrupt";
  };
}
```
