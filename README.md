# foot-incus-ssh-tmux-osc52 POC

I created this POC to set up a terminal emulator based on the following stack: [foot](https://codeberg.org/dnkl/foot) → ssh → an [LXC](https://github.com/lxc/lxc) container or a [QEMU](https://www.qemu.org/) VM managed by [Incus](https://linuxcontainers.org/incus/) → [tmux](https://github.com/tmux/tmux/).

## Objectives

This environment must support the following features:

- [x] Multiple foot instances connect to a single shared tmux session but can display different windows (tmux session groups, see [tmux FAQ](https://github.com/tmux/tmux/wiki/FAQ#how-do-i-attach-the-same-session-to-multiple-clients-but-with-a-different-current-window-like-screen--x))
- [x] Implement bidirectional copy-paste via OSC52 across the whole foot → ssh → tmux chain
  - [x] Chain bricks (prerequisite)
    - [x] tmux on the instance: `~/.tmux.conf` with `set-clipboard on`, `get-clipboard both`, `mouse on`, `terminal-features 'foot:clipboard'` (image `build-image/fedora.yaml` + live)
    - [x] foot local: `[security] osc52=enabled` (`assets/foot.ini`)
    - [x] Manual check in a focused foot window, end-to-end: copy-mode copy reaches the host clipboard
    - [x] Manual check in a focused foot window, end-to-end: mouse selection in a pane reaches the host clipboard
    - [x] `tmux info | grep Ms` reports an `Ms` entry
  - [x] Acceptance (manual, end-to-end over the whole foot → ssh → tmux → nvim chain, in a new `mise run console` window)
    - [x] copy nvim → host: `y` on a selection, then paste on the host (`wl-paste`)
    - [x] copy nvim → host: large yank (200+ lines) arrives complete
    - [x] paste host → nvim: `wl-copy "text"` on the host, then `p` in nvim inserts it
    - [x] paste host → nvim: large clipboard (100+ KiB) pastes completely, without "Waiting for OSC 52 response" or timeout
    - Note: foot only honors OSC-52 clipboard reads/writes from a window that has keyboard focus (unfocused attempts are dropped with a `warn: osc.c … unfocused` log, no foot option to relax this). Since tmux broadcasts copies to all attached clients, keep the console you copy/paste from focused and ignore these warnings on other consoles.
- [x] Implement image display in the terminal
  - Note: foot implements a single image protocol, **SIXEL** (kitty/iTerm2 graphics protocols are deliberately not supported upstream, see [dnkl/foot#481](https://codeberg.org/dnkl/foot/issues/481)). SIXEL escapes are transparent over ssh, and images reach the local foot either:
    - **via tmux passthrough** (`allow-passthrough on`, tmux ≥ 3.3) — the quality path: foot renders the sixel stream itself, at full resolution. Used by `image.nvim` (sixel backend, it wraps the stream in `\ePtmux;…`) and by `chafa --passthrough`.
    - **via tmux native SIXEL** (`terminal-features 'foot:sixel'`, requires a tmux built with `--enable-sixel`, Fedora ships it) — fallback for tools emitting raw sixel (`img2sixel`, `chafa` without passthrough). tmux SIXEL handling is basic, quality is reduced and images are not tracked on redraws (see [tmux#4436](https://github.com/tmux/tmux/issues/4436)).
  - Acceptance (manual, end-to-end over the whole foot → ssh → tmux → nvim chain, in a new `mise run console` window)
    - [x] Terminal (foot → ssh, no tmux: `ssh -t … bash`): `chafa --format=sixel ~/poc.jpg` shows a sharp image
    - [x] Terminal, full chain: `chafa --format=sixel --passthrough=auto ~/poc.jpg` shows a sharp image in a tmux pane
    - [x] Terminal, native fallback: `img2sixel ~/poc.jpg` shows an image (reduced quality acceptable)
    - [x] nvim image buffer: `nvim ~/poc.jpg` renders the photo (image.nvim `hijack_file_patterns`)
    - [x] nvim markdown: a doc with `![](poc.jpg)` renders inline when the cursor is on the image
    - [x] Robustness: pane scroll, window resize, two foot consoles attached to the same grouped session → no crash, image redraws (some artifacts on scroll are expected for sixel)
    - Note: sixel is palette-limited (256 colors) and an image pushed through tmux passthrough is *not* part of the tmux screen grid, so tmux-initiated redraws/scrolls can leave or erase it until the app redraws. Keep the test console focused.
  - Test protocol & implementation details: see [docs/image-display.md](docs/image-display.md)
- [x] Implement opening remote URLs in the local host's browser
  - Note: two complementary paths, both validated on the real desktop (see [docs/remote-desktop-link.md](docs/remote-desktop-link.md)): **automatic** — tools running in the instance call `xdg-open`, wrapped to reach the desktop portal (`org.freedesktop.portal.OpenURI`) over the unix-socket dbus forward, so the URL opens in the local host's default browser; **manual** — a URL merely *displayed* in the console is opened with foot URL mode (`Ctrl+Shift+o`, keyboard-driven, no instance component). foot does not support click-to-open.
  - Acceptance (manual, end-to-end over the whole foot → ssh → tmux chain, in a new `mise run console` window, carrier up)
    - [x] automatic: `xdg-open https://example.com` run in the instance opens the local host's default browser
    - [x] a second grouped console does not duplicate the open (the dbus call is not broadcast to every console)
    - [x] robustness: carrier down → `xdg-open` fails cleanly with no side effect on the host; restart the carrier (re-run `mise run console`) → works again
    - [x] manual fallback: `printf 'https://example.com\n'`, then `Ctrl+Shift+o` on the focused console and open it → browser opens on the local host
    - Note: the URL is opened by the desktop session that owns the forwarded bus (foot host default handler/browser profile).
- [x] Implement forwarding of remote notifications to the local desktop
  - Note: remote `notify-send` posts to the desktop notification daemon (`org.freedesktop.Notifications`, present on the foot host) over the same unix-socket dbus forward. Unlike terminal-OSC mechanisms this has no foot-focus requirement and no duplication across consoles. Transport & implementation choices: see [docs/remote-desktop-link.md](docs/remote-desktop-link.md).
  - Acceptance (manual, end-to-end over the whole foot → ssh → tmux chain, in a new `mise run console` window, carrier up)
    - [x] `notify-send test hello` in the instance shows a desktop notification on the local host
    - [x] notification from a background task (`sleep 15; notify-send …`) is shown while the console is not the focused window
    - [x] one call = one notification, even with two consoles attached to the grouped session
    - [x] robustness: carrier restart → `notify-send` works again; no crash or hang when the daemon or carrier is unreachable
- [x] Implement streaming of sound generated remotely to the local host's audio output
  - Note: instance audio clients (`paplay`, `pactl`, any libpulse app) play on the foot host's PipeWire/Pulse server via the unix-socket pulse forward; no audio daemon runs on the instance. Transport & implementation choices: see [docs/remote-desktop-link.md](docs/remote-desktop-link.md).
  - Acceptance (manual, end-to-end over the whole foot → ssh → tmux chain, in a new `mise run console` window, carrier up)
    - [x] `paplay` a test sound in the instance → audible on the local host's default output
    - [x] `pactl info` in the instance reports the foot host's Pulse server (`Is Local: yes`)

If this POC is successful, I want to reuse this implementation to migrate the [`sklein-devbox`](https://github.com/stephane-klein/sklein-devbox/) project from a podman base to [Incus](https://linuxcontainers.org/incus/).

Related resource: [`incus-poc`](https://github.com/stephane-klein/incus-poc).

## Reference documentation

The reference documents explain the details and implementation choices behind
the objectives above:

- [docs/remote-desktop-link.md](docs/remote-desktop-link.md) — the reverse-SSH
  carrier that gives the instance access to the foot host's desktop (automatic
  URL opening, notifications, audio), why it forwards unix sockets rather than
  TCP, and its components and failure modes.
- [docs/image-display.md](docs/image-display.md) — SIXEL image display in the
  terminal and nvim over the foot → ssh → tmux chain (the two transport paths,
  bricks, limitations) and its acceptance test protocol.

## Known issue — SIXEL > ~1.07 k px silently dropped in the tmux chain (paused)

SIXEL images wider than ~1.07 k px are silently dropped **in the tmux layer of
this POC's chain** (measured on instance tmux 3.7c: `img2sixel -w 1068`
displayed, `-w 1069` not, whatever the foot window / tmux pane size). A control
on 2026-09-06 showed foot **standalone** renders images up to 2000 px wide
(110×109 and 284×79 windows), so foot is not at fault. Inside tmux the drop is
sticky (nothing displays again until the console is reopened) and also hit the
passthrough route at large sizes.

Consequence for the image tests below: while using tmux keep **raw** sixel
output ≤ ~1068 px wide (`chafa --size` / `img2sixel -w`, moderate console
width); do not widen the console too far during the tests.

Still an open problem, investigation paused. Full report, measurements and
analysis scripts: [`foot-sixel-size-bug/`](foot-sixel-size-bug/).

## Getting started

### Build Incus LXC Fedora image

See [`./build-image/`](./build-image/).

### Deploy Incus LXC Fedora instance

```sh
$ mise install
$ mise run deploy-lxc
$ mise run enter-in-lxc
[fedora@foot-incus-ssh-tmux-osc52-poc ~]$
```

## Step-by-step acceptance walkthrough

This walkthrough replays, by hand, every acceptance test listed in the
Objectives section above, end to end over the whole foot → ssh → tmux chain. The
instance must be deployed and reachable first (see the Deploy Incus LXC Fedora
instance section above).

- Each console is opened on the foot host with `mise run console`. Every
  invocation also (re)starts the remote-desktop link carrier
  (`foot-link.service`) that forwards the foot host's session bus and audio
  server to the instance; the URL, notification and audio scenarios need it up.
- Keep the console you are testing **focused**: foot only honors OSC-52
  clipboard reads/writes from the focused window, and image redraws are more
  reliable there. tmux broadcasts clipboard copies to every attached console,
  so the others log `warn: osc.c … unfocused` — harmless, ignore them.

### Shared tmux session groups, independent current window per console

Goal: several foot consoles attach to the same shared tmux session (session
groups, the `screen -x` model) but each keeps its own current window.

- Open a first console on the host:

  ```
  $ mise run console
  ```

- Type some text, e.g. `echo "console 1, window 1"`.
- Open a new tmux window and type different text:
  - `Ctrl-b c` creates the window;
  - type `echo "console 1, window 2"`;
  - switch windows with `Ctrl-b n` (next) / `Ctrl-b p` (previous).
- Open a second console on the host, in a new terminal:

  ```
  $ mise run console
  ```

- In console 2, navigate with `Ctrl-b n` / `Ctrl-b p` to a window different
  from the one console 1 currently shows.

Expected: both consoles share the same windows and panes, but each displays the
window you chose for it independently. Text typed in a window on one console is
visible on the other as soon as it shows the same window.

### Bidirectional OSC52 copy-paste (foot → ssh → tmux → nvim)

Preflight — check tmux can set the clipboard on foot:

```
$ tmux info | grep Ms
```

Expected: the output contains an `Ms` entry (foot ships `osc52=enabled`, tmux
`set-clipboard on` / `terminal-features 'foot:clipboard'`).

Then run the four scenarios in a **focused** `mise run console` window, with
nvim.

- Copy nvim → host:
  - `printf 'one\ntwo\nthree\n' > /tmp/clipboard-test.txt`, open it with
    `nvim /tmp/clipboard-test.txt`, visually select some lines (`v`, then move),
    press `y`;
  - on the host, in a plain terminal: `wl-paste` shows the selected text.
- Large yank (200+ lines) arrives complete:
  - `seq 1 300 > /tmp/clipboard-big.txt`, open `nvim /tmp/clipboard-big.txt`,
    `ggVG` selects everything, press `y`;
  - on the host: `wl-paste | wc -l` reports 300.
- Paste host → nvim:
  - on the host: `wl-copy "pasted from host"`;
  - in nvim, place the cursor where you want the text and press `p`; the text
    is inserted.
- Large clipboard (100+ KiB) pastes completely, without "Waiting for OSC 52
  response" or timeout:
  - on the host, build a text bigger than 100 KiB, check its size, and put it
    in the clipboard:
    ```
    $ yes "some fairly long line to exceed one hundred KiB of text content" | head -n 4000 > /tmp/clipboard-huge.txt
    $ wc -c /tmp/clipboard-huge.txt   # ~250000 bytes, i.e. > 100 KiB
    $ wl-copy < /tmp/clipboard-huge.txt
    ```
  - in nvim, press `p`; the whole content is pasted.

> foot only honors OSC-52 clipboard reads/writes from the window that has
> keyboard focus; unfocused attempts are dropped with a
> `warn: osc.c … unfocused` log and there is no foot option to relax this.
> Since tmux broadcasts copies to all attached consoles, keep the console you
> copy from focused and ignore these warnings on the other consoles.

### Image display (SIXEL)

Preparation (once, on the instance) — download a Creative Commons test photo
(Wikimedia Commons, CC BY-SA 4.0,
[file page](https://commons.wikimedia.org/wiki/File:J%C3%A6ren_Naust.jpg)):

```
$ curl -fL -o ~/poc.jpg 'https://commons.wikimedia.org/wiki/Special:FilePath/J%C3%A6ren_Naust.jpg'
```

Fine detail and smooth gradients in the photo make resolution easy to eyeball.
Full test protocol and implementation details: [docs/image-display.md](docs/image-display.md).

> Known issue (paused; tmux layer, foot exonerated on 2026-09-06): SIXEL
> images wider than ~1.07 k px silently disappear **inside the tmux chain**,
> whatever the window/pane size, and tmux then keeps dropping images until the
> console is reopened. `chafa --format=sixel` scales to the window width, so a
> wide or maximized console can push the image over the limit. Keep this console
> at a moderate width (`mise run console` opens 100×55) and do not resize or
> maximize it during the tests; or constrain the emitter
> (`chafa --size` / `img2sixel -w`). Details, measurements and analysis
> scripts: [foot-sixel-size-bug/](foot-sixel-size-bug/).

- foot → ssh, no tmux (isolate foot + ssh): in a fresh foot window, bypass the
  ssh tmux wrapper, then render:
  ```
  $ ssh -t fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info bash
  $ chafa --format=sixel ~/poc.jpg
  ```
  Expected: sharp image with crisp detail. If it fails here, foot or ssh is the
  problem — do not continue (the ~1 k px drop described above is specific to
  the tmux chain, not to this foot → ssh path).
- Full chain in a terminal (foot → ssh → tmux): in a `mise run console` window,
  compare both transport paths:
  ```
  $ chafa --format=sixel --passthrough=auto ~/poc.jpg   # quality path (tmux passthrough)
  $ img2sixel ~/poc.jpg                                 # native sixel fallback
  ```
  Expected: both display an image; the passthrough one is sharp (if it is not,
  retry with `--passthrough=tmux`), the `img2sixel` one may have reduced
  quality, which is acceptable.
- nvim image buffer:
  ```
  $ nvim ~/poc.jpg
  ```
  Expected: image.nvim hijacks the file and renders the photo in the buffer
  (`:lua print(require("image").is_enabled())` → `true`).
- nvim markdown inline:
  ```
  $ printf 'inline image:\n\n![poc](poc.jpg)\n' > ~/poc.md
  $ nvim ~/poc.md
  ```
  Expected: when the cursor is on the `![poc]` line, the image renders inline
  (`only_render_image_at_cursor`).
- Robustness:
  - scroll the tmux pane, resize the foot window, trigger redraws → no crash,
    the image reappears (some artifacts on scroll are expected for sixel);
  - attach a second `mise run console` to the same grouped session and switch
    windows → images follow the window each console displays;
  - keep the tested console focused.

### Opening URLs in the local browser

Requires the remote-desktop link carrier to be up (started by
`mise run console`). Implementation details:
[docs/remote-desktop-link.md](docs/remote-desktop-link.md).

- Automatic — open a URL from the instance:
  ```
  $ xdg-open https://example.com
  ```
  Expected: the URL opens in the foot host's default browser.
- A second grouped console does not duplicate the open:
  - open another `mise run console` and re-run `xdg-open https://example.com`;
  - expected: exactly one open (the D-Bus portal call is not broadcast to
    every console).
- Manual fallback — open a URL merely displayed in the console:
  ```
  $ printf 'https://example.com\n'
  ```
  Press `Ctrl+Shift+o` (foot URL mode), select the URL, open it. Expected: the
  browser opens on the local host; this path needs no instance component.
- Robustness — carrier down:
  - on the foot host: `systemctl --user stop foot-link.service`;
  - in the console: `xdg-open https://example.com` fails cleanly with a D-Bus
    error and no side effect on the host;
  - restart the carrier (`systemctl --user start foot-link.service`, or simply
    re-run `mise run console`), then `xdg-open` works again.

> The URL is opened by the desktop session that owns the forwarded bus (the
> foot host's default handler/browser profile).

### Desktop notifications

Requires the remote-desktop link carrier to be up.

- Basic call:
  ```
  $ notify-send "test" "hello"
  ```
  Expected: a desktop notification appears on the foot host.
- From a background task while the console is not focused:
  ```
  $ sleep 15; notify-send "later" "still delivered"
  ```
  Expected: switch to another window or console; after 15 s the notification
  shows even though the tested console has no keyboard focus (no foot-focus
  requirement here).
- One call = one notification: with two consoles attached to the grouped
  session, run a single `notify-send`; expected exactly one notification, not
  one per console.
- Robustness — carrier restart: `systemctl --user restart foot-link.service`
  (or re-run `mise run console`), then `notify-send` works again; when the
  daemon or the carrier is unreachable the call fails cleanly, without crash or
  hang.

### Sound on the local host

Requires the remote-desktop link carrier to be up.

- Play a sound from the instance — download a Creative Commons test recording
  (church bell, Wikimedia Commons, CC BY-SA 4.0,
  [file page](https://commons.wikimedia.org/wiki/File:Samariter_Church_bell_I_(Es)_01.ogg)):
  ```
  $ curl -fL -o ~/test.ogg 'https://commons.wikimedia.org/wiki/Special:FilePath/Samariter_Church_bell_I_(Es)_01.ogg'
  $ paplay ~/test.ogg
  ```
  Expected: the bell ring is audible on the foot host's default output.
- Check which audio server the instance talks to:
  ```
  $ pactl info
  ```
  Expected: reports the foot host's PipeWire/Pulse server, with `Is Local: yes`.

