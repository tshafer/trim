# Trim

*Trim — the set of a ship's sails; also, to cut away the excess.*

Drop an image on Trim and it cuts the dead margin away from the artwork — the
transparent border around an exported logo, the sea of white around a chart, the
solid backdrop around a product shot. In the spirit of QuickCrop, but free: one
window, one slider, live preview, done.

## Features

- Drop an image (or ⌘O to open, ⌘V to paste from the clipboard) and Trim scans
  the bitmap in one pass to find the tightest box around the actual content.
- Detects a solid uniform background of *any* color by sampling the four
  corners — not just white and transparent margins.
- Or choose the background yourself: white, black, transparency only, or a
  specific color eyedropped straight off the image (⌘P, then click a pixel).
- One tolerance slider (0–100) widens or tightens what counts as background;
  the crop recomputes live off the main thread as you drag.
- Trim only the edges you want. Lock the top, right, bottom, or left and that
  side is left exactly where it was.
- Aspect ratio lock (1:1, 4:3, 3:2, 16:9, or the original ratio) grows the crop
  around its center until it fits the shape, without ever leaving the canvas.
- Live preview with dimmed margins and a crisp crop outline, before → after
  pixel dimensions, how many pixels came off each side, and a padding stepper
  to keep N px of breathing room.
- Export options: PNG, JPEG (with a quality slider), or TIFF, at 25%, 50%,
  100%, or 200% scale. JPEG output is flattened onto white so transparent
  margins don't come out black.
- Export: ⌘S saves, ⌘C copies the cropped image, or just drag the preview out
  to Finder.
- Batch: drop several images, review them in the sidebar, step through them
  with ⌘↓/⌘↑, and "Trim All…" exports every one to a folder of your choice
  with a `-trimmed` suffix.
- Images with no trimmable margin say so plainly ("already tight") instead of
  pretending to help.
- Every setting sticks between launches; "Reset to defaults" lives in the
  Options popover.

## Build

```
./make-app.sh
```

Builds a release binary with Swift Package Manager, wraps it into Trim.app,
installs it to /Applications, and launches it. No Xcode project, no
dependencies.

## Permissions

None. Trim reads the files you hand it and writes where you tell it. No
network, no analytics.
