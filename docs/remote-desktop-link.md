# Remote-desktop link: URL, notifications and audio from the instance to the foot host

The terminal chain foot → ssh → tmux gives the Incus instance an interactive
desktop-less shell, but a terminal emulator only speaks escape sequences. foot
can relay clipboard (OSC 52) and images (SIXEL), but it has **no** channel to
open a browser, post a desktop notification or play audio on behalf of a remote
program.

To give the remote instance access to the desktop of the machine running foot
(the "foot host"), a persistent reverse-SSH **carrier** exposes two resources of
the foot host to the instance over loopback-only **unix sockets**:

| Instance program | Uses | Forward |
|---|---|---|
| `/usr/local/bin/xdg-open` (URL opening) | desktop portal `org.freedesktop.portal.OpenURI` | session D-Bus (`/tmp/foot-host-bus`) |
| `notify-send` (notifications) | `org.freedesktop.Notifications` | session D-Bus (`/tmp/foot-host-bus`) |
| `paplay`, `pactl` (audio) | PipeWire/Pulse server | `/tmp/foot-host-pulse` |

Opening URLs by hand when they are merely *displayed* in the console stays
available through foot URL mode (`Ctrl+Shift+o`); see
[foot](https://codeberg.org/dnkl/foot) documentation. This document covers the
**automatic** path (remote `xdg-open`), notifications and audio.

## Architecture

```
foot host (desktop)                              Incus instance (headless)
─────────────────────                            ─────────────────────────
systemd --user                                   ┌ /tmp/foot-host-bus     ← session bus
foot-link.service  ── ssh -N -R ─────────────────┤  DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/foot-host-bus
  /run/user/<uid>/bus                            ├────────────────────────────────────────────
  /run/user/<uid>/pulse/native                   └ /tmp/foot-host-pulse   ← audio (PipeWire/Pulse)
                                                     PULSE_SERVER=unix:/tmp/foot-host-pulse
```

The carrier is started from the `mise run console` task (see below), so each
console session guarantees the link exists. The consoles themselves are
unaffected; the link is an extra, dedicated ssh connection.

```sh
ssh -N -T \
  -R /tmp/foot-host-bus:%t/bus \
  -R /tmp/foot-host-pulse:%t/pulse/native \
  fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info
```

`%t` is the systemd user runtime dir of the foot host (`/run/user/<uid>`),
resolved by the unit. sshd creates `/tmp/foot-host-bus` and
`/tmp/foot-host-pulse` on the instance when the connection is up and removes
them when it closes.

## Design decisions

### Forward unix sockets to unix sockets, not TCP

The obvious approach is a TCP forward + a remote address:

```sh
ssh -R 127.0.0.1:34567:/run/user/<uid>/bus ...
export DBUS_SESSION_BUS_ADDRESS=tcp:host=127.0.0.1,port=34567
```

This **fails** against the desktop session bus:

```
Error connecting: Exhausted all available authentication mechanisms (tried: EXTERNAL)
```

The session bus only accepts `EXTERNAL` authentication. On a TCP transport the
client claims its own uid, which does not match the peer credentials the D-Bus
daemon sees on *its* socket (the local ssh process). Copying
`~/.dbus-keyrings` would not help: this bus does not offer
`DBUS_COOKIE_SHA1`.

With a **unix → unix** forward (`-R /tmp/foo.sock:/run/user/<uid>/bus`,
supported since OpenSSH ≥ 6.7, verified on OpenSSH 10.0) the *local ssh
process* connects to the bus socket itself, so `EXTERNAL` is resolved from its
peer credentials — the desktop user — regardless of the uid the instance-side
client claims. **This works.**

### The same reasoning applies to audio

PipeWire/Pulse treats a client that connects to its unix socket
(`/run/user/<uid>/pulse/native`) as **local**: same peer credentials, no cookie
exchange. Forwarded over a unix socket, `paplay`/`pactl` in the instance reach
the foot host's audio server without sharing any Pulse cookie.

### Trust model and security

Opening the desktop **session bus** to the instance means any program running
there can use everything the desktop user can over D-Bus (notifications,
portal, GNOME services, secrets), and can ask the desktop to open URLs and to
play audio. This matches the trust already granted for the clipboard over
OSC 52 — the instance is a first-class remote terminal. The forwards only ever
bind to loopback sockets on the instance and stay inside the encrypted ssh
connection; nothing is exposed on the netbird LAN.

## Components and files

### Foot host

- [`scripts/foot-link.service`](../scripts/foot-link.service) — systemd **user**
  unit running the two `-R` forwards (`Restart=on-failure`,
  `ExitOnForwardFailure`, keep-alive options).
- [`../.mise.toml`](../.mise.toml), task `console` — installs the unit under
  `~/.config/systemd/user`, runs `daemon-reload` + `start`, then opens foot.
  Non-blocking: if no systemd user manager is available, a warning is printed
  and the console still opens.

### Instance bricks

Baked into the image ([`../build-image/fedora.yaml`](../build-image/fedora.yaml),
applied *live* too, same "image + live" pattern as the other features):

- Packages: `libnotify` (`notify-send`), `pulseaudio-utils` (`paplay`,
  `pactl`).
- `/usr/local/bin/xdg-open` — wrapper replacing the (headless-failing) system
  `xdg-open`; it calls the portal `OpenURI` method on the forwarded bus:

  ```
  gdbus call --session --dest org.freedesktop.portal.Desktop \
    --object-path /org/freedesktop/portal/desktop \
    --method org.freedesktop.portal.OpenURI.OpenURI \
    '' "$url" '{}'
  ```

- `/etc/profile.d/foot-host-link.sh` and an `export` block in
  `/usr/local/bin/ssh-tmux-login` — both set:

  ```
  DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/foot-host-bus
  PULSE_SERVER=unix:/tmp/foot-host-pulse
  ```

- sshd drop-in `StreamLocalBindUnlink yes` so a stale listener socket left by a
  crashed session is unlinked on the next bind.

## Behaviour and operational notes

- **Environment propagation.** The exports in `ssh-tmux-login` apply when a
  tmux server is (re)started. For a server that is already running, the two
  variables were added to its *global environment* (`tmux set-environment -g`),
  so **new panes** inherit them. Panes created *before* the change keep their
  old environment: they may point at the instance's own empty session bus
  (`/run/user/1000/bus`) or at nothing. Open a fresh pane (or restart the tmux
  servers) after changing the configuration.
- **Failure modes.** Carrier down → `notify-send`/`xdg-open` fail with a
  D-Bus error, `paplay` with `Connection refused`; nothing hangs. Restart the
  carrier by re-running `mise run console` (or `systemctl --user restart
  foot-link.service` on the foot host).
- **Diagnosis.** From the instance: `pactl info` reports `Is Local: yes`;
  `gdbus call --session --dest org.freedesktop.DBus --object-path
  /org/freedesktop/DBus --method org.freedesktop.DBus.GetNameOwner
  org.freedesktop.Notifications` returns an owner.

## What was validated

Validated end-to-end (P0 spike) from the instance against the **real** desktop
session bus and PipeWire of the foot host:

- D-Bus over the unix forward: `ListNames` and `GetNameOwner` (portal and
  notifications daemon present) succeed; `notify-send` posts a notification.
- Audio over the unix forward: `pactl info` succeeds, silent playback to a
  null sink works, audible playback reaches the desktop default sink.
- URL opening: the `OpenURI` portal call opens the desktop default browser.

The acceptance checklists live in the README ("Objectives" section) and are the
manual, end-to-end tests over the whole foot → ssh → tmux chain.
