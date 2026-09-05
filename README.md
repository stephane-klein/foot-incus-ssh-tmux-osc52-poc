# foot-incus-ssh-tmux-osc52 POC

I created this POC to set up a terminal emulator based on the following stack: [foot](https://codeberg.org/dnkl/foot) → ssh → an [LXC](https://github.com/lxc/lxc) container or a [QEMU](https://www.qemu.org/) VM managed by [Incus](https://linuxcontainers.org/incus/) → [tmux](https://github.com/tmux/tmux/).

## Objectives

This environment must support the following features:

- [x] Multiple foot instances connect to a single shared tmux session but can display different windows (tmux session groups, see [tmux FAQ](https://github.com/tmux/tmux/wiki/FAQ#how-do-i-attach-the-same-session-to-multiple-clients-but-with-a-different-current-window-like-screen--x))
- [ ] Implement bidirectional copy-paste via OSC52 across the whole foot → ssh → tmux chain
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
