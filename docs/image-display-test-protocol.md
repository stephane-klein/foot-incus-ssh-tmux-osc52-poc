# Image display over foot → ssh → tmux → nvim — test protocol

Target: display an image in the terminal and inside nvim, over the whole chain
foot (local, Wayland) → ssh → Incus LXC (Fedora) → tmux → shell/nvim.

Protocol transport is **SIXEL** (the only image protocol foot implements). The
image is encoded remotely (`chafa`, `img2sixel`, or ImageMagick `sixel:-`) and
reaches foot either through tmux passthrough (`allow-passthrough on`, full
quality) or through tmux native SIXEL (`terminal-features 'foot:sixel'`,
reduced quality).

## Sample image

Created once, remotely, self-contained (no binary in the repo):

```sh
magick -size 900x500 gradient:'#8aadf4'-'#24273a' -fill white -gravity center \
  -pointsize 36 -annotate +0-40 'foot -> ssh -> tmux' \
  -pointsize 36 -annotate +0+30 'image display (SIXEL)' ~/poc.png
```

The white text over a blue gradient makes resolution/quality easy to eyeball:
legible text ⇒ the image reached foot at full quality.

## P0 — Preflight (automated, run over plain ssh, no tmux console needed)

```sh
ssh fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info '
  echo "1. tmux sixel_support        : $(tmux display -p -t main -F "#{sixel_support}")"   # expect 1
  echo "2. allow-passthrough         : $(tmux show -g allow-passthrough | cut -d" " -f2)"  # expect on
  echo "3. terminal-features foot    : $(tmux show -g terminal-features | grep foot)"       # expect ...:clipboard and ...:sixel
  echo "4. focus-events / vis-act    : $(tmux show -g focus-events | cut -d" " -f2)/$(tmux show -g visual-activity | cut -d" " -f2)" # on/off
  echo "5. magick sixel output       : $(magick ~/poc.png sixel:- | head -c 2 | od -An -tx1 | tr -d " ")"  # expect 1b50 (ESC P)
  echo "6. img2sixel output          : $(img2sixel ~/poc.png 2>/dev/null | head -c 2 | od -An -tx1 | tr -d " ")" # expect 1b50
  echo "7. IM sixel coder            : $(magick -list format 2>/dev/null | grep -c SIXEL) formats"  # expect >= 1
  echo "8. image.nvim installed      : $(test -d ~/.local/share/nvim/site/pack/vendor/start/image.nvim && echo yes)"
'
```

Any non-expected value breaks the matching brick (foot / tmux / encoder / nvim)
before any visual test.

## P1 — foot → ssh, no tmux (isolate foot + ssh)

In a fresh foot window, bypass the ssh ForceCommand tmux wrapper:

```sh
ssh -t fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info bash
chafa --format=sixel ~/poc.png
```

Expected: sharp image, text legible. If it fails here, foot or ssh is the
problem — do not continue.

## P2 — full chain, terminal (foot → ssh → tmux)

In a `mise run console` foot window (regular tmux console):

```sh
chafa --format=sixel --passthrough=auto ~/poc.png   # quality path
img2sixel ~/poc.png                                 # native sixel fallback (quality may drop)
```

Expected: image visible in both cases. Compare sharpness between the two to
confirm passthrough engages (if `--passthrough=auto` yields no/lower quality,
retry with `--passthrough=tmux`).

## P3 — nvim image buffer

```sh
nvim ~/poc.png
```

Expected: image.nvim hijacks the PNG and renders it in the buffer
(`:lua print(require("image").is_enabled())` → `true`).

## P4 — nvim markdown inline

```sh
printf 'inline image:\n\n![poc](poc.png)\n' > ~/poc.md
nvim ~/poc.md
```

Move the cursor over/onto the `![poc]` line: expected the inline image to
render (markdown integration `only_render_image_at_cursor = true`).

## P5 — robustness

- Scroll the tmux pane, resize the foot window, redraw: no crash, image
  reappears (sixel may leave/clear artifacts on tmux-initiated redraws — the
  passthrough stream is not part of the tmux grid).
- Attach a second foot console to the same grouped session and switch windows:
  images follow the window the console displays; keep the tested console
  focused.

## Known limitations

- SIXEL is palette-based (≈256 colors, 0–100 component range) and foot does
  not implement kitty/iTerm2 graphics protocols (see
  [dnkl/foot#481](https://codeberg.org/dnkl/foot/issues/481)).
- tmux native SIXEL support is basic: lower quality and images not fully
  tracked on redraws ([tmux#4436](https://github.com/tmux/tmux/issues/4436));
  prefer the passthrough path for quality.
