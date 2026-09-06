# SIXEL images > ~1068 px silently dropped — in the tmux chain, foot exonerated

Investigation archive. Status on 2026-09-06: **foot is not at fault** — the
silent drop happens in the **tmux** layer of the foot → ssh → tmux chain. The
problem is still present on our side; investigation **paused** by the author.

## Context

This subfolder started as "foot silently drops SIXEL images wider than ~1.07
k px", measured on the foot → ssh chain of this POC with the CC test photo
`~/poc.jpg` (Wikimedia Commons, 5874×3549). A control re-test on 2026-09-06
showed the premise was wrong: the failing runs had gone through the **tmux**
session spawned by `assets/foot.ini` (`shell=/usr/bin/tmux new-session`); the
"no tmux" label in the original notes was inaccurate.

## Re-test 2026-09-06 (decisive)

Environment: single foot binary on the host `1.28.0-3-g180df200 (Sep 06 2026,
branch 'master')`; instance tmux **3.7c**, pane 284×79, `TERM=tmux-256color`,
`allow-passthrough on` and `terminal-features 'foot:sixel'` already set in
`~/.tmux.conf`; photo `~/poc.jpg`.

| Chain | Probe | Result |
|---|---|---|
| foot → ssh → bash (**no tmux**) | `img2sixel -w` 1068 / 1069 / 1200 / 1500 / **2000** | **all displayed** (windows 110×109 and 284×79, incl. after resize) |
| foot → ssh → tmux | `chafa --format=sixel --size=102x62` | displayed |
| foot → ssh → tmux | `img2sixel -w 1069` (fresh window, first command) | **not displayed** |
| foot → ssh → tmux | `img2sixel -w` ≥ 1069 after a first failure | **sticky**: nothing more until the foot window is reopened |
| foot → ssh → tmux | `chafa --format=sixel --passthrough=none --size=150x80` | **not displayed** |
| foot → ssh → tmux | `chafa --format=sixel --passthrough=tmux --size=150x80` | no clean image (raw characters) |
| foot → ssh → tmux | `tmux set -ga terminal-overrides ',foot:passthrough'` then `img2sixel -w 2000` | still **not displayed** (img2sixel never wraps in tmux passthrough, so not conclusive) |

Conclusions:

- **foot standalone has no such cap**: SIXEL up to 2000 px wide renders in both
  110×109 and 284×79 windows, before and after resize.
- The ~1068 px silent drop reproduces **only through tmux**; it is silent,
  pane-size-independent (it fails at ~1068 px in a 284-col ≈ 2556 px pane) and
  sticky per foot window until reopened.
- tmux 3.7c native SIXEL handling of raw emitters (`img2sixel`, `chafa` without
  passthrough) is the suspect layer; the passthrough route did not produce a
  clean large image either on this re-test.
- **Still an open problem with tmux on our side; investigation paused.**

## Measurements (original, kept for history)

| Probe | Window | Result |
|---|---|---|
| `chafa --format=sixel` (auto size, window ≤ ~100 cols) | default / 100×55 | displayed |
| `chafa --format=sixel` (auto size, window > ~100 cols) | 200×55, maximized, fullscreen | not displayed |
| `chafa --size=102x62` | 284×79 **and** 110×109 | displayed |
| `chafa --size=103x63` | 284×79 **and** 110×109 | not displayed |
| `img2sixel -w 1068` (≈ 1068×645 px) | 110×109 | displayed |
| `img2sixel -w 1069` (≈ 1069×646 px) | 110×109 | not displayed |

These runs were recorded as "foot, no tmux" at the time, but the test windows
opened the tmux spawned by `assets/foot.ini` (only `-e ssh … bash` bypasses it).
"Threshold identical whatever the window size" is consistent with a drop in the
tmux layer, not with a foot cap tied to the viewport. The earlier cell-width
inference (chafa ~102 cells ≈ img2sixel ~1068 px → "foot cell ≈10.5 px") is not
meaningful: `foot -d info` reports a 9 px cell width on this setup.

## Conclusion (current)

- **foot is not the culprit**: it renders SIXEL ≥ 2000 px wide standalone.
- The silent drop ≥ ~1069 px lives in the **tmux layer** of this POC's chain
  (tmux 3.7c with `--enable-sixel`); it is pane-size-independent and sticky per
  foot window.
- Practical rule for this POC while using tmux: keep **raw** sixel output
  ≤ ~1068 px wide (`img2sixel -w 1068`, `chafa --size=102x62`, moderate console)
  and treat large images as unreliable until tmux handles them better.
  foot-standalone consoles have no measured limit.

## Status

**Not reported to foot upstream, and must not be: the re-test exonerates foot.**
[`issue-template.md`](issue-template.md) is kept as an archive and is marked
superseded. A follow-up, if any, would target the **tmux** tracker
(github.com/tmux/tmux). Investigation paused by the author on 2026-09-06.

## Related foot upstream issues (historical context)

These foot issues were the original reason to suspect foot's sixel sizing code;
after the re-test they do not look related to this symptom, and are kept only as
context:

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

Both scripts are interactive (human answers "visible ? [y/n]" after each probe).
They are meant to measure the drop threshold **inside the tmux chain**, where
the symptom reproduces: run them in a foot → ssh console whose session is the
shared tmux one, at a fixed pane size (do not resize afterwards). They assume
the test photo exists on the instance (`~/poc.jpg`, overridable with
`IMG=/path/image.jpg`).

### Setup

From the foot host (this repo):

```sh
scp -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR foot-sixel-size-bug/scripts/*.sh \
  fedora@foot-incus-ssh-tmux-osc52-poc.homelab.stephane-klein.info:
```

Open the test console (this opens the tmux session of the chain):

```sh
foot --config assets/foot.ini --window-size-chars=110x109
```

or, for the foot-standalone control that now serves as the baseline (bypasses
the tmux spawned by the config):

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

Interpretation: inside the tmux chain the threshold does not move between the
110×109 and 284×79 foot windows (the tmux pane keeps its size), which is why
the symptom looked like a fixed cap. Compare with the foot-standalone control
(`-e ssh … bash`) to separate the layers.

### `img2sixel-width-bisect.sh` — find the pixel limit via img2sixel

Bisects the **image width in pixels** (`img2sixel -w`, which emits exact pixel
dimensions with no cell logic). Pins the drop threshold in pixels.

```sh
bash ~/img2sixel-width-bisect.sh        # default bounds 500..4000 px
bash ~/img2sixel-width-bisect.sh 500 4000
```

Output: `OK px w=1068 | echec px w=1069`.

Use `IMG=/path/to/image.jpg` for a different source (e.g. a portrait image to
discriminate width vs height vs area caps).
