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
    - [x] Terminal (foot → ssh, no tmux: `ssh -t … bash`): `chafa --format=sixel ~/poc.png` shows a sharp image
    - [x] Terminal, full chain: `chafa --format=sixel --passthrough=auto ~/poc.png` shows a sharp image in a tmux pane
    - [x] Terminal, native fallback: `img2sixel ~/poc.png` shows an image (reduced quality acceptable)
    - [x] nvim image buffer: `nvim ~/poc.png` renders the PNG (image.nvim `hijack_file_patterns`)
    - [x] nvim markdown: a doc with `![](poc.png)` renders inline when the cursor is on the image
    - [x] Robustness: pane scroll, window resize, two foot consoles attached to the same grouped session → no crash, image redraws (some artifacts on scroll are expected for sixel)
    - Note: sixel is palette-limited (256 colors) and an image pushed through tmux passthrough is *not* part of the tmux screen grid, so tmux-initiated redraws/scrolls can leave or erase it until the app redraws. Keep the test console focused.
  - Test protocol: see [docs/image-display-test-protocol.md](docs/image-display-test-protocol.md)
- [ ] Implement opening remote URLs in the local host's browser
- [ ] Implement forwarding of remote notifications to the local desktop
- [ ] Implement streaming of sound generated remotely to the local host's audio output

If this POC is successful, I want to reuse this implementation to migrate the [`sklein-devbox`](https://github.com/stephane-klein/sklein-devbox/) project from a podman base to [Incus](https://linuxcontainers.org/incus/).

Related resource: [`incus-poc`](https://github.com/stephane-klein/incus-poc).

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
