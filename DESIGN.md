---
name: Snapparazzi
description: One macOS window, recorded; a site typeset entirely in amber phosphor characters on a single monospace grid.
colors:
  phosphor-amber: "#ffb341"
  phosphor-amber-hot: "#ffc66e"
  amber-dim: "#d39a45"
  amber-trace: "#6b4f26"
  cathode-black: "#0c0a07"
typography:
  glyph-display:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace"
    fontSize: "7px"
    fontWeight: 400
    lineHeight: 1
    letterSpacing: "0"
  headline:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace, PingFang TC, Noto Sans TC, Heiti TC, sans-serif"
    fontSize: "clamp(22px, 2.4vw, 32px)"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "-0.01em"
  lede:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace, PingFang TC, Noto Sans TC, Heiti TC, sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.7
  body:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace, PingFang TC, Noto Sans TC, Heiti TC, sans-serif"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.7
  code:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace, PingFang TC, Noto Sans TC, Heiti TC, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.6
    fontFeature: "\"tnum\" 1"
  label:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace, PingFang TC, Noto Sans TC, Heiti TC, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.7
    letterSpacing: "0.08em"
  scene:
    fontFamily: "Martian Mono, ui-monospace, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.18
    letterSpacing: "0"
spacing:
  gutter: "clamp(16px, 4vw, 64px)"
  step: "clamp(56px, 6vw, 96px)"
  cell-x: "2ch"
  row-y: "16px"
components:
  button-copy:
    backgroundColor: "{colors.phosphor-amber}"
    textColor: "{colors.cathode-black}"
    typography: "{typography.label}"
    rounded: "0px"
    padding: "0 2ch"
  button-copy-hover:
    backgroundColor: "{colors.phosphor-amber-hot}"
    textColor: "{colors.cathode-black}"
  button-copy-active:
    backgroundColor: "{colors.amber-dim}"
    textColor: "{colors.cathode-black}"
  button-copy-done:
    backgroundColor: "{colors.cathode-black}"
    textColor: "{colors.phosphor-amber}"
  toggle-lang:
    backgroundColor: "transparent"
    textColor: "{colors.phosphor-amber}"
    rounded: "0px"
    padding: "2px 1ch"
  toggle-lang-pressed:
    backgroundColor: "{colors.phosphor-amber}"
    textColor: "{colors.cathode-black}"
  nav-link:
    textColor: "{colors.phosphor-amber}"
    typography: "{typography.label}"
  nav-link-current:
    backgroundColor: "{colors.phosphor-amber}"
    textColor: "{colors.cathode-black}"
  command-row:
    textColor: "{colors.phosphor-amber}"
    typography: "{typography.code}"
    padding: "12px 1.5ch"
  terminal-block:
    textColor: "{colors.phosphor-amber}"
    typography: "{typography.code}"
    padding: "12px 2ch"
---

# Design System: Snapparazzi

## Overview

**Creative North Star: "The Phosphor Desktop"**

Every surface is a screen drawn in typewriter characters: one amber phosphor ink on a near-black cathode, one strict monospace grid, and nothing that is not a character. Tone is not a colour choice; it is glyph density, running from the period to the at-sign, and the densest glyph is the highlight. The recorded window is the densest mass on the page; everything not being recorded is pushed to the sparse end of the ramp.

Structure is typed, never drawn. Boxes are rows of `+-- label ---+`, rules are rows of `- - -` or `: : :`, and links sit in brackets. Active things are inverse cells, a solid amber block with black characters, the way a terminal shows a selection. There are no images, no gradients, no shadows, no rounded corners and no second hue.

The page is dense and quiet at once: small type (13–15px), generous section steps, and a single live scene that moves. Motion is the grid resolving itself: glyphs scramble and settle left to right, the REC mark and caret blink, and reduced motion shows the settled frame.

**Key Characteristics:**
- One hue (amber) in three strengths on one ground; tone comes from glyph density.
- Martian Mono for everything on the grid; CJK falls back to the system Traditional Chinese face.
- Display headlines are rendered as glyph density, not set in a display face.
- Frames and rules are typed ASCII characters, not CSS borders.
- Active state is always an inverse cell.

## Colors

A single amber phosphor ink at three strengths on a warm near-black; no other hue exists.

### Primary
- **Phosphor Amber** (`--ink`): all primary text, glyph headlines, the densest scene glyphs, and every inverse cell (copy button, pressed language, current nav item, menubar, REC and `-w` tags, text selection).
- **Hot Phosphor** (hover only): the copy button's hover fill, one step brighter on the same hue. Never used at rest.

### Neutral
- **Dim Amber** (`--ink-2`): secondary text: notes, step descriptions, spec definitions, captions, prompts (`$`, `> `), frame labels, the pressed copy button's active flash.
- **Amber Trace** (`--ink-3`): typed rules, frame rows, nav brackets, link underlines and the scrollbar thumb. Marks only, never readable text.
- **Cathode Black** (`--bg`): the ground, and the text colour inside inverse cells. Also the `theme-color`.

### Named Rules
**The One Hue Rule.** Every colour is amber or the black ground. A second hue, a gradient or a tint of anything else breaks the world.

**The Trace Is Not Text Rule.** Amber Trace carries rules, brackets and underlines only; anything a visitor must read is Phosphor Amber or Dim Amber.

## Typography

**Display Font:** none as such; display lines are glyph-density renders on the grid.
**Body Font:** Martian Mono (self-hosted variable woff2, weights 100–800, width 75–112.5%), with ui-monospace, Menlo; CJK falls back to PingFang TC, Noto Sans TC, Heiti TC.
**Label/Mono Font:** the same Martian Mono; there is only one family.

**Character:** a technical, slightly condensed mono (page set at `font-stretch: 87.5%`) that reads like a terminal manual; character grids (`pre`) reset to 100% width so cells stay square to the ramp.

### Hierarchy
- **Glyph display** (rendered at 7px / 5px under 600px, line-height 1): the hero headline and the closing line. Text is drawn at weight 800 into a canvas, sampled per cell, and printed as a three-level fill: `@` for solid interior (≥0.7), `%` for edges, space below the cutoff (0.25 for CJK, 0.35 for Latin, which is uppercased). The real heading stays in the DOM, visually hidden, as the accessible source.
- **Headline** (700, clamp(22px, 2.4vw, 32px), 1.25, max 28ch, balanced): section titles, always prefixed with a Dim Amber `> ` prompt.
- **Lede** (400, 16px, 1.7, max 46ch): the hero's two lines of copy.
- **Body** (400, 15px / 14px under 600px, 1.7): running text; descriptions max 42–70ch.
- **Code** (400, 13px, 1.6, tabular numerals): command rows and terminal blocks. Inline code in prose is 700 weight in Phosphor Amber.
- **Label** (13px, 0.08em, uppercase in the top bar): brand, nav, language toggle, install label, notes and status.
- **Scene / rules** (12px; scene 9px under 600px; line-height 1.18 for the scene, 1 for rules): the ASCII desktop and typed rule rows.

### Named Rules
**The Glyph Headline Rule.** Large type is never set in a large font; it is rendered through the density ramp into a `pre` with the source heading kept for assistive tech.

**The One Grid Rule.** Every visible character belongs to the Martian Mono grid; widths and indents are measured in `ch` wherever the grid shows.

## Layout

Edges are a fluid gutter (`spacing.gutter`), sections are separated by a fluid step (`spacing.step`) and a typed rule. The hero is a 5/12 + 7/12 grid (copy and install left, live scene right), at least the viewport tall up to 920px. Content blocks use a 4/12 + 8/12 split (step text against its terminal; spec term against definition). Inside frames, horizontal padding is in characters (1.5–2ch, 5ch for the caveat list's `!` hang) and rows are 16px apart.

At 960px and below every split collapses to one column and the scene loses its minimum height. At 600px and below the top bar wraps (nav drops to its own row, language toggle stays right), the copy button stacks under the command, the scene drops to 9px and glyph headlines to 5px.

## Elevation & Depth

Flat. There are no shadows, blurs or layered surfaces. Depth is density: the recorded window is drawn through the full ramp with a solid `-`/`|`/`+` frame and sits on top, while other windows drop to `.`/`:` frames and sparse content. Emphasis is the inverse cell, not a lift.

### Named Rules
**The Density Is Depth Rule.** To bring something forward, make it denser or invert it; never shadow, blur or tint it.

## Shapes

No radius anywhere; every edge is square because it is a cell edge. Containers are typed frames: a head row `+-- label ------+` (label in Dim Amber, dashes in Amber Trace, filled to the column with a flex row) above the block and a bare `+------+` row below, with no side walls. Section rules are a spaced dash row (`- - -`) in Amber Trace at 12px; rows inside a list or spec are separated by a spaced colon row (`: : :`). Links take brackets `[ ]` in the nav; the copy button prints its own `[ 複製 ]`.

## Components

### Buttons
- **Shape:** a square inverse cell (0 radius), height taken from the command row it sits in.
- **Copy (primary):** Phosphor Amber fill, Cathode Black text, 700 13px with 0.06em tracking, label in brackets (`[ 複製 ]` / `[ COPY ]`), 2ch side padding.
- **Hover / Active:** fill brightens to Hot Phosphor on hover and drops to Dim Amber on press (200ms, `cubic-bezier(.16,1,.3,1)`).
- **Done:** inverts back (black fill, amber text) with the "copied" label, announced through a polite live region, then restores.

### Language Toggle
- **Style:** `[中|EN]` with Dim Amber brackets and bar; buttons are transparent amber text, 1ch padding.
- **State:** the pressed language is an inverse cell; the other shows a 14% amber wash on hover (250ms ease-out). Choice persists in localStorage; first visit follows the browser language.

### Navigation
- **Style:** uppercase 13px labels at 0.08em, each in Amber Trace brackets that turn Phosphor Amber on hover.
- **Current:** the section in view (scroll-spied) becomes an inverse cell, brackets included.
- **Mobile:** wraps to its own full-width row under the brand.

### Command Row
- **Style:** a typed frame around `$ ` + the command (13px, wraps anywhere) with the copy button flush right; stacks vertically under 600px.

### Terminal Block
- **Style:** a typed frame labelled like a shell tab (`+-- zsh 1/3`), `pre` content at 13px/1.6 with 2ch padding; the prompt and output are Dim Amber, the typed command Phosphor Amber. Output is real CLI text.

### Spec List
- **Style:** term/definition rows (700 term, Dim Amber definition) or caveat rows hung on a bold `!`, separated by `: : :` rules, inside a typed frame.

### ASCII Desktop Scene (signature)
A live Mac desktop in characters on the ramp ` .:-=+*#%@`. An inverse menubar runs across the top. The targeted window is the densest mass, framed solid and wrapped in `+--` viewfinder corners with an inverse blinking `REC mm:ss` tag above and an inverse `-w <id>` tag below; the other windows are dotted frames with sparse content. Pointer, tap or arrow keys retarget; the command line under the scene retypes the new window ID behind a blinking block caret. The scene animates only while visible; reduced motion paints a static frame on demand.

### Motion
Glyph content resolves with a left-to-right scramble: unresolved columns flicker through the ramp, then settle to the `@`/`%` fill, over 900ms with exponential ease-out (`1 - 2^(-10p)`), triggered as each glyph headline enters view. REC blinks at 1Hz, the caret at 1.1s steps. Under `prefers-reduced-motion` everything appears resolved and nothing blinks.

## Do's and Don'ts

### Do:
- **Do** draw boxes and rules as typed characters (`+`, `-`, `|`, `:`, brackets) on the grid, in Amber Trace.
- **Do** show every active or selected state as an inverse cell: Phosphor Amber fill, Cathode Black text.
- **Do** render large headlines through the glyph-density fill (`@`, `%`, space) and keep the real heading as the accessible source.
- **Do** measure grid-aligned padding and indents in `ch`.
- **Do** give every animation a resolved static state for reduced motion.

### Don't:
- **Don't** introduce a second hue, a gradient, an image or a photograph; tone comes only from glyph density.
- **Don't** use CSS borders, border-radius or box-shadow to build containers or depth.
- **Don't** set Amber Trace (`--ink-3`) on readable text.
- **Don't** set a headline in a large display font in place of the glyph render.
- **Don't** let any non-recorded element out-dense the recorded window in the scene.
