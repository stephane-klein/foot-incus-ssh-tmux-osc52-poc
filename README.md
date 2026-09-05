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
- [ ] Implement image display in the terminal
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
