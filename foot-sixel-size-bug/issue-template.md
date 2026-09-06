# (ARCHIVE — superseded) Issue draft: SIXEL images > ~1069 px silently dropped in the tmux chain

> **STATUS: SUPERSEDED — DO NOT POST (foot re-tested 2026-09-06)**
>
> The silent cap described in this draft was **not reproducible on foot alone**.
> On the current build `1.28.0-3-g180df200` (Sep 06 2026), foot **standalone**
> renders SIXEL images up to 2000 px wide (windows 110×109 and 284×79, resize
> included). The drop reproduces only **through the tmux layer** of this POC's
> chain (instance tmux 3.7c, native SIXEL path): silent, sticky until the foot
> window is reopened, independent of the pane geometry (fails at ~1068 px in a
> 284-col pane). The original runs assumed "no tmux", but the windows had opened
> the tmux spawned by `assets/foot.ini` (`shell=/usr/bin/tmux new-session`).
>
> This issue is therefore **misattributed to foot** and must **not** be posted
> on the foot tracker. Kept here as an archive of the original measurements; a
> follow-up, if any, would target the tmux tracker. Decisive re-test and full
> analysis: [`README.md`](README.md).
>
> Prepared with AI assistance (OpenCode, DeepSeek V4 Flash) — see
> "Preparation note" below.
>
> Title used for this archive draft: `SIXEL images silently not displayed above
> a fixed ~1069 px width cap in the tmux chain (foot exonerated)`.

---

### Foot Version

- `foot version: 1.27.0-37-ge5916a02 (Jul 27 2026, branch 'master') -pgo +ime +graphemes +toplevel-tag +blur -assertions` — historical; binary no longer installed, not re-testable
- `foot version: 1.28.0-3-g180df200 (Sep 06 2026, branch 'master') -pgo +ime +graphemes +toplevel-tag +blur -assertions` — re-tested 2026-09-06 on this build (foot exonerated, see STATUS)

### TERM environment variable

`foot`

### Compositor Name and Version

GNOME / Mutter, Wayland (please fill exact Mutter version)

### Distribution

Fedora (please fill exact release)

### Terminal multiplexer

tmux 3.7c — the failing runs went through the tmux spawned by the config; the
original "No response" answer was wrong (see STATUS)

### Shell, TUI, application

bash (interactive, over `ssh -t`, inside the config-spawned tmux); `chafa` 1.18.2, `img2sixel` 1.10.5

### Server/standalone mode

- [x] Standalone
- [ ] Server

### Foot config

`assets/foot.ini` from the POC, **not** the default foot.ini (differences are
cosmetic and OSC-52 related only; no sixel-related option is set):

```ini
[main]
font=Hack Nerd Font Mono:size=11
shell=/usr/bin/tmux new-session
term=foot

[security]
osc52=enabled

[csd]
preferred=none
size=0
border-width=0

# Catppuccin color themes for foot.
# Source: https://github.com/catppuccin/foot (themes/catppuccin-macchiato.ini and themes/catppuccin-latte.ini)
# Switch theme at runtime with SIGUSR1 (dark) / SIGUSR2 (light)

[colors-dark]
cursor=181926 f4dbd6
foreground=cad3f5
background=24273a
alpha=0.99
regular0=494d64
regular1=ed8796
regular2=a6da95
regular3=eed49f
regular4=8aadf4
regular5=f5bde6
regular6=8bd5ca
regular7=b8c0e0
bright0=5b6078
bright1=ed8796
bright2=a6da95
bright3=eed49f
bright4=8aadf4
bright5=f5bde6
bright6=8bd5ca
bright7=a5adcb
selection-foreground=cad3f5
selection-background=454a5f

[colors-light]
cursor=eff1f5 dc8a78
foreground=4c4f69
background=eff1f5
alpha=0.99
regular0=5c5f77
regular1=d20f39
regular2=40a02b
regular3=df8e1d
regular4=1e66f5
regular5=ea76cb
regular6=179299
regular7=acb0be
bright0=6c6f85
bright1=d20f39
bright2=40a02b
bright3=df8e1d
bright4=1e66f5
bright5=ea76cb
bright6=179299
bright7=bcc0cc
selection-foreground=4c4f69
selection-background=ccced7

[environment]
TERM=foot

[key-bindings]
spawn-terminal=Control+Shift+n
color-theme-toggle=Control+Shift+F5
```

Windows are opened with:
`foot --config assets/foot.ini --window-size-chars=110x109`

### Description of Bug and Steps to Reproduce

> **Re-test 2026-09-06** — this report is superseded: foot **standalone** does
> not cap (SIXEL ≥ 2000 px renders). The drop below is specific to the **tmux
> layer** of this POC's chain and is kept here only as the historical repro.
> Decisive data: [`README.md`](README.md).

SIXEL images are **silently not displayed** once they exceed a fixed size,
whatever the terminal window size. Smaller images always display, including
after a window resize. No error is logged on screen; only closing and reopening
the foot window "resets" the behaviour (because a smaller image is then drawn).
Note that the window opened below runs the tmux spawned by the config
(`shell=/usr/bin/tmux new-session`), which is where the drop happens.

Reproduction with `img2sixel` (exact pixel dimensions, no cell logic):

1. Open a foot window (config above), e.g. `foot --config assets/foot.ini --window-size-chars=110x109`.
2. Run `img2sixel -w 1068 test.jpg` → image is displayed (~1068×645 px).
3. Run `img2sixel -w 1069 test.jpg` → **nothing is displayed** (~1069×646 px).

Reproduction with `chafa` (cell-based scaling):

1. Open the same window.
2. `chafa --format=sixel --size=102x62 test.jpg` → displayed.
3. `chafa --format=sixel --size=103x63 test.jpg` → **not displayed**.

Key observation (historical): the threshold is **identical in very different
window sizes** (110×109 rows and 284×79 rows both fail between `--size=102x62`
and `--size=103x63`, and between `img2sixel -w 1068` and `-w 1069`). This was
read at the time as a fixed foot-side cap independent of the visible viewport;
the 2026-09-06 re-test showed it is a **tmux-layer** drop (constant tmux pane,
foot standalone unaffected).

Test image: any aspect ratio ~1.65:1 landscape photo (here 5874×3549).

### Expected behavior

Terminals like xterm render SIXEL images larger than a threshold by scrolling
(or clamping); foot should either display them or report why it drops them. A
fixed silent cap around 1 k px is surprising: the same stream displays below
the cap and vanishes above it.

### Observed behavior

Above the cap (~1069 px wide, `img2sixel`), foot displays nothing, no partial
image, no message. Text output keeps working. Images that are small enough
display reliably, before and after window resizes.

### Related upstream issues

- #2343 — heap buffer overflow in sixel.c (`CSI ? 2 ; 3 ; W ; H S` huge dims)
- #2355 — PR clamping max sixel width/height (fix for #2343)
- #2372 — heap-buffer-overflow in `sixel_add_many_generic` / `sixel_add_many_ar_11`
- #155 — sixels in the scrolling margins

None of these describes this exact symptom, but all touch the same sixel
sizing/decoding code. This report was filed after re-testing on a build
including the #2355 clamp; the cap was still reproducible, so it is not the
crash path but the *displayed* size limit.

### Preparation note (transparency)

This bug report was prepared with the assistance of an AI coding assistant
(OpenCode, model `deepseek/deepseek-v4-flash`). The AI helped structure the
report and analyse the collected data; all measurements, reproduction steps
and environment checks were performed manually by the reporter, and the final
text was reviewed before posting.

### Relevant logs

<!-- Fill by running: foot -d info --config … -e … and reproducing -->
```
info: main.c:…: version: …
info: wayland.c:…: monitor: …
```
No sixel-specific error appears in the logs at the failing size; happy to
provide full `foot -d info` output on request.
