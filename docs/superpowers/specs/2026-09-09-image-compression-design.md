# Snapparazzi Image Compression Design

## Goal

Reduce long-running capture storage without making one-frame-per-second workloads expensive or removing the existing lossless option.

## CLI behavior

Snapparazzi 1.1.0 defaults to full-resolution JPEG and adds:

```text
-f, --format <jpg|heic|png>
-m, --max-dimension <pixels>
```

`jpeg` is accepted as an alias and normalized to `jpg`. The maximum dimension must be a positive integer. PNG remains available for lossless output, while HEIC offers the smallest full-resolution files with weaker cross-tool compatibility. Filenames use the selected extension.

Image format and optional maximum dimension work in both interactive and argument-driven capture modes. They are shown in startup output and documented in bilingual help and README content.

## Encoding and performance

`screencapture` writes JPEG, HEIC, or PNG directly so Snapparazzi never creates a temporary PNG merely to compress it. When a maximum dimension is requested, `/usr/bin/sips -Z` resizes the captured image in place while preserving its aspect ratio and never enlarging it.

Benchmarks on the user's 35 existing 2560×1410 Chrome captures:

| Output | Average frame | Projected 16 hours at 1 fps | Processing time per frame |
|---|---:|---:|---:|
| PNG | 1.30 MB | 74.9 GB | ~0.11 s direct capture |
| JPEG quality 80 reference | 404 KB | 23.3 GB | ~0.04–0.08 s |
| HEIC quality 80 reference | 213 KB | 12.3 GB | ~0.14–0.19 s |
| JPEG, max dimension 1280 | 136 KB | 7.9 GB | ~0.06–0.14 s |

Actual sizes vary with screen content. Direct `screencapture` encoder quality is system-controlled; Snapparazzi does not add a misleading quality option.

## Failure handling and compatibility

Unsupported formats and invalid dimensions fail before requesting screen-recording permission with exit status 2. Capture or resize failures remove incomplete output and count as runtime failures. `Ctrl-C` interrupts whichever child process is active.

Existing PNG sessions are untouched. The release updates source, tests, bilingual help, README, CI, installed binary, `main`, and tag `v1.1.0`.
