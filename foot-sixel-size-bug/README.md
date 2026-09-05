# foot bug: sixel images beyond a fixed size are silently not displayed

## Context

Investigated on the foot → ssh → bash chain of this POC (no tmux), GNOME/Wayland
desktop, while re-running the image-display acceptance tests with the CC test
photo `~/poc.jpg` (Wikimedia Commons, 5874×3549).

When a SIXEL image is emitted above a fixed size, **foot displays nothing** —
no error, no partial image — until the window is closed and reopened. Smaller
images always display, whether the window has been resized or not.

## Measurements

Encoders used: `chafa` 1.18.2 (scales in terminal cells) and `img2sixel` 1.10.5
(libsixel, scales in pixels).

| Probe | Window | Result |
|---|---|---|
| `chafa --format=sixel` (auto size, window ≤ ~100 cols) | default / 100×55 | displayed |
| `chafa --format=sixel` (auto size, window > ~100 cols) | 200×55, maximized, fullscreen | not displayed |
| `chafa --size=102x62` | 284×79 **and** 110×109 | displayed |
| `chafa --size=103x63` | 284×79 **and** 110×109 | not displayed |
| `img2sixel -w 1068` (≈ 1068×645 px) | 110×109 | displayed |
| `img2sixel -w 1069` (≈ 1069×646 px) | 110×109 | not displayed |

The threshold is **identical for very different window sizes** (79 and 109 rows)
→ it is a fixed cap, not tied to the visible viewport. With foot's cell width
(≈10.5 px) the chafa limit (~102 cells) matches the img2sixel pixel limit
(~1068 px): foot drops SIXEL images wider than roughly **1.07 k px**.

## Conclusion

- The bug is in **foot's handling of large sixel images**, not in the encoders:
  the same bytes display fine below the cap and are dropped above it, regardless
  of window geometry.
- For this POC, image tests must keep images **≤ ~1000 px wide** (e.g. a foot
  window of ~100 columns, or constrain the emitter with `chafa --size` /
  `img2sixel -w`).
- Open question: is the cap on width, height, or total area? A portrait test
  image would discriminate.

## Status

**Not reported upstream yet.** See `issue-template.md` for the ready-to-paste
issue text. It is intentionally not posted until the upstream sixel-sizing
fixes below have landed and the cap has been re-measured (the cap may move or
start logging once foot clamps sixel dimensions).

## Related upstream issues

None of these covers this exact symptom (silent drop above a fixed size), but
they all live in foot's sixel sizing/decoding code (`sixel.c`) and are the
reason to re-test before posting:

- [#2343](https://codeberg.org/dnkl/foot/issues/2343) — heap buffer overflow in
  sixel.c: `CSI ? 2 ; 3 ; W ; H S` accepts huge dimensions without clamping
  (crash).
- [#2355](https://codeberg.org/dnkl/foot/pulls/2355) — PR "sixel: clamp max
  width/height in `CSI ? 2 ; 3 ; W ; H S`", fix for #2343.
- [#2372](https://codeberg.org/dnkl/foot/issues/2372) — heap-buffer-overflow in
  `sixel_add_many_generic` / `sixel_add_many_ar_11` (crash).
- [#155](https://codeberg.org/dnkl/foot/issues/155) — sixels in the scrolling
  margins (sixel + scroll handling).

## Analysis scripts

Both scripts are interactive (human answers "visible ? [y/n]" after each probe)
and are meant to run **inside the instance**, in a foot → ssh console. They
assume the test photo exists on the instance (`~/poc.jpg`, overridable with
`IMG=/path/image.jpg`).

### Setup

From the foot host (this repo):

```sh
scp -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR foot-sixel-size-bug/scripts/*.sh \
  fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info:
```

Open a test console with a fixed window size and **do not resize it afterwards**:

```sh
foot --config assets/foot.ini --window-size-chars=110x109 -e ssh -t \
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info bash
```

### `sixel-height-scan.sh` — find the height limit in chafa cells

Scans the image **height** (in terminal cells) for a fixed aspect ratio,
clearing the screen between probes and asking the operator whether the image is
visible after each one.

```sh
bash ~/sixel-height-scan.sh scan 80 5     # linear scan, H from 20 to 80 step 5
bash ~/sixel-height-scan.sh bisect 60 65  # refine around the first failure
```

Output (bisect): `dernier OK: H=62 | premier echec: H=63 | window=… (w_emise=…)`.

Interpretation: run it in two different window sizes (e.g. 110×109 and 284×79).
If the threshold does not move, the limit is fixed (foot-side cap), not a
viewport effect.

### `img2sixel-width-bisect.sh` — find the pixel limit via img2sixel

Bisects the **image width in pixels** (`img2sixel -w`, which emits exact pixel
dimensions with no cell logic). Pins the cap in pixels for the ticket.

```sh
bash ~/img2sixel-width-bisect.sh        # default bounds 500..4000 px
bash ~/img2sixel-width-bisect.sh 500 4000
```

Output: `OK px w=1068 | echec px w=1069`.

Use `IMG=/path/to/image.jpg` for a different source (e.g. a portrait image to
discriminate width vs height vs area caps).
