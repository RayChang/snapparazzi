---
version: 1
slug: "site-index-html"
primary_target: "site/index.html"
related_targets: []
---

# Surface: GitHub Pages landing page (site/index.html)

Mode: Persuade. Visitor: a Mac user who wants to keep a record of an automated run in one app window (timed screenshots first; video with sound when needed); comfortable pasting a command into Terminal. Action: copy the install command, then start a first capture. Proof: the real CLI's own commands and messages, and a live demonstration of picking one window out of a desktop. Constraints: static HTML/CSS/JS in site/, deployed by GitHub Actions; zh-TW and English switched by a toggle (default follows the browser, remembered per visitor); no invented users, numbers or testimonials; illustrative windows are labeled as an illustration.

Below the first viewport the page is Read, not Persuade: the owner found the README clearer than the first version of the page (too little detail, scattered, no obvious first step). It follows the README's order and facts in one column: Start here (install, permission, find the ID, start), Timed screenshots (options, measured file sizes, where files go), Recording (options, sound, window state, stopping, measured), Permissions and more. Both languages are written in full and switched by the toggle.

## Direction contract

THESIS: The page is a live scene rendered in typewriter characters, and the scene is a Mac desktop: one window is picked out and recorded while every other window stays sparse. It refuses the category default of a dark hero, a terminal screenshot and a grid of feature cards.

OWN-WORLD: Black ground with a single amber phosphor ink; tone comes only from glyph density, running from period to at-sign, and the densest glyph is the highlight. One strict monospace character grid (Martian Mono) carries all type, rules and boxes. Boxes and rules are drawn with plain ASCII (+, -, |, :) and brackets. Active elements are inverse cells. There are no images, gradients or second hue.

STORY: The visitor sees that Snapparazzi captures one window, not the screen: by default it snaps a screenshot every 2 s (a SNAP counter and a shutter flash), and a [SNAP|RECORD] switch shows the video mode. Moving the pointer re-targets the capture and the command updates with that window's ID. Then they learn the three commands, the sound options and the limits, copy the install line, and leave.

FIRST VIEWPORT: The top bar holds the name, version, numbered section links and a [中|EN] toggle. On the left (5/12), the headline is rendered as glyph density ("只錄一個視窗" / "ONE WINDOW."), followed by two lines of copy and the install command row with a working [COPY] button, which is the primary action. On the right (7/12), the ASCII desktop: four windows, the targeted one dense inside a blinking REC viewfinder, and under it the live command `snapparazzi record -w <id>`.

FORM: Challenger medium-native-ascii-live-scene-render (adopted by the user over the assigned badge sheet; owner then chose the full ASCII world). seed:94ef5e584f6e3968

Signature interaction: pointer (or tap / arrow keys) moves the viewfinder between windows; the scene re-renders through the glyph ramp and the command line retypes. Motion grammar: glyph scramble-resolve when content appears; reduced motion shows the resolved state.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
