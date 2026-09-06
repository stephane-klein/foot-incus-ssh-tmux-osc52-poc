# Image display in the terminal (SIXEL)

Displaying images — in the shell and inside nvim — over the whole chain
foot (local, Wayland) → ssh → Incus LXC (Fedora) → tmux.

A terminal emulator renders whatever bytes arrive on its input; for an image to
appear, the remote program must emit an image stream that foot understands.
foot implements a single image protocol: **SIXEL**.

## Why SIXEL and not something else

- foot deliberately supports only SIXEL; the kitty and iTerm2 graphics
  protocols are not implemented upstream
  ([dnkl/foot#481](https://codeberg.org/dnkl/foot/issues/481)).
- SIXEL escape sequences are plain text bytes: they travel unchanged through
  `ssh` (no special transport, no port, no tunnel).
- SIXEL is palette-limited (≈256 colors, 0–100 component range).

An image is therefore encoded remotely (`chafa`, `img2sixel`, ImageMagick
`sixel:-`, image.nvim) and the resulting SIXEL stream reaches local foot.

## How the SIXEL stream reaches foot — two paths

tmux sits in the middle and normally swallows escape sequences it does not
understand. Two bricks make images cross tmux:

1. **tmux passthrough (quality path).** With `allow-passthrough on` (tmux ≥
   3.3), an application can wrap its stream in `\ePtmux;…\e\\` and tmux forwards
   it **verbatim** to the outer terminal. foot then renders the SIXEL stream
   itself, at full resolution. This is how `image.nvim` (sixel backend) and
   `chafa --passthrough` work.
2. **tmux native SIXEL (fallback).** With `terminal-features 'foot:sixel'`
   (requires a tmux built with `--enable-sixel`, which Fedora ships), tmux
   parses *raw* SIXEL emitted in a pane (`img2sixel`, `chafa` without
   passthrough) and forwards it. tmux SIXEL handling is basic: reduced quality,
   and images are not tracked on redraws
   ([tmux#4436](https://github.com/tmux/tmux/issues/4436)). On tmux 3.7c this
   path also silently drops images wider than ~1.07 k px (see Known
   limitations).

Consequence of the two paths: an image pushed through passthrough is *not* part
of the tmux screen grid, so tmux-initiated redraws or scrolls can leave it
stale or erase it until the application redraws. Keep the tested console
focused.

## Bricks and files

All image bricks live on the **instance**, in the image build
[`../build-image/fedora.yaml`](../build-image/fedora.yaml) (applied *live* the
same way):

- Packages: `chafa`, `ImageMagick`, `libsixel-utils` (and tmux with SIXEL
  support, part of Fedora's build).
- `~/.tmux.conf` (written by a post-packages action): `set -g
  allow-passthrough on` (path 1), `set -ag terminal-features 'foot:sixel'`
  (path 2), plus `set -g focus-events on` needed by image.nvim to show/hide
  images across tmux windows.
- nvim config (`~/.config/nvim/init.lua`): clipboard over OSC 52 + `image.nvim`
  (pinned tag v1.5.1) configured with `backend = "sixel"`,
  `processor = "magick_cli"`, and the markdown integration
  `only_render_image_at_cursor = true`.

No change is required in `assets/foot.ini` for images.

## Known limitations

- SIXEL is palette-based (≈256 colors); foot does not implement kitty/iTerm2
  graphics protocols
  ([dnkl/foot#481](https://codeberg.org/dnkl/foot/issues/481)).
- tmux native SIXEL is basic (lower quality, images not tracked on redraws);
  prefer the passthrough path.
- A passthrough image is not part of the tmux grid: tmux-initiated
  scrolls/redraws can leave artifacts until the app redraws.
- SIXEL wider than ~1.07 k px is silently dropped **inside the tmux chain** of
  this POC (native path, raw emitters like `img2sixel` / `chafa` without
  passthrough; sticky until the console is reopened). A 2026-09-06 control
  showed foot standalone renders ≥ 2000 px wide — foot is not at fault. While
  using tmux keep test images ≤ ~1068 px wide (moderate window or
  `chafa --size` / `img2sixel -w`). Investigation paused. Full report and
  analysis scripts:
  [`../foot-sixel-size-bug/`](../foot-sixel-size-bug/).

## Annex — acceptance test protocol

The acceptance of this feature is manual and end-to-end over the whole foot →
ssh → tmux → nvim chain, run in a new `mise run console` window.

### Sample image

A Creative Commons test photo, fetched once, remotely, self-contained (no
binary in the repo), Wikimedia Commons CC BY-SA 4.0
([file page](https://commons.wikimedia.org/wiki/File:J%C3%A6ren_Naust.jpg)):

```sh
curl -fL -o ~/poc.jpg 'https://commons.wikimedia.org/wiki/Special:FilePath/J%C3%A6ren_Naust.jpg'
```

The photo's fine detail and smooth gradients make resolution/quality easy to
eyeball: crisp detail and no visible color banding ⇒ the image reached foot at
full quality.

### P0 — Preflight (automated, run over plain ssh, no tmux console needed)

```sh
ssh fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info '
  echo "1. tmux sixel_support        : $(tmux display -p -t main -F "#{sixel_support}")"   # expect 1
  echo "2. allow-passthrough         : $(tmux show -g allow-passthrough | cut -d" " -f2)"  # expect on
  echo "3. terminal-features foot    : $(tmux show -g terminal-features | grep foot)"       # expect ...:clipboard and ...:sixel
  echo "4. focus-events / vis-act    : $(tmux show -g focus-events | cut -d" " -f2)/$(tmux show -g visual-activity | cut -d" " -f2)" # on/off
  echo "5. magick sixel output       : $(magick ~/poc.jpg sixel:- | head -c 2 | od -An -tx1 | tr -d " ")"  # expect 1b50 (ESC P)
  echo "6. img2sixel output          : $(img2sixel ~/poc.jpg 2>/dev/null | head -c 2 | od -An -tx1 | tr -d " ")" # expect 1b50
  echo "7. IM sixel coder            : $(magick -list format 2>/dev/null | grep -c SIXEL) formats"  # expect >= 1
  echo "8. image.nvim installed      : $(test -d ~/.local/share/nvim/site/pack/vendor/start/image.nvim && echo yes)"
'
```

Any non-expected value breaks the matching brick (foot / tmux / encoder / nvim)
before any visual test.

### P1 — foot → ssh, no tmux (isolate foot + ssh)

In a fresh foot window, bypass the ssh ForceCommand tmux wrapper:

```sh
ssh -t fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info bash
chafa --format=sixel ~/poc.jpg
```

Expected: sharp image, crisp detail. If it fails here, foot or ssh is the
problem — do not continue.

### P2 — full chain, terminal (foot → ssh → tmux)

In a `mise run console` foot window (regular tmux console):

```sh
chafa --format=sixel --passthrough=auto ~/poc.jpg   # quality path
img2sixel ~/poc.jpg                                 # native sixel fallback (quality may drop)
```

Expected: image visible in both cases. Compare sharpness between the two to
confirm passthrough engages (if `--passthrough=auto` yields no/lower quality,
retry with `--passthrough=tmux`). Note: in a very wide pane the raw `img2sixel`
image (> ~1.07 k px) is silently dropped by tmux native SIXEL (see Known
limitations) — keep the console at a moderate width for this test.

### P3 — nvim image buffer

```sh
nvim ~/poc.jpg
```

Expected: image.nvim hijacks the file and renders the photo in the buffer
(`:lua print(require("image").is_enabled())` → `true`).

### P4 — nvim markdown inline

```sh
printf 'inline image:\n\n![poc](poc.jpg)\n' > ~/poc.md
nvim ~/poc.md
```

Move the cursor over/onto the `![poc]` line: expected the inline image to
render (markdown integration `only_render_image_at_cursor = true`).

### P5 — robustness

- Scroll the tmux pane, resize the foot window, redraw: no crash, image
  reappears (sixel may leave/clear artifacts on tmux-initiated redraws — the
  passthrough stream is not part of the tmux grid).
- Attach a second foot console to the same grouped session and switch windows:
  images follow the window the console displays; keep the tested console
  focused.
