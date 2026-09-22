#ifndef NFBMediaTransitionGeometry_h
#define NFBMediaTransitionGeometry_h
#include <math.h>
#include <stdbool.h>
// Twitter 9.67: TFNFullscreenMediaTransitionDefaultDuration.
static const double NFBMediaOpeningDuration = 0.25;
typedef struct { double x, y, width, height; } NFBMediaTransitionRect;
// Preserve the thumbnail's aspect-fill crop while its clipping window expands
// into the fullscreen aspect-fit frame. Coordinates are local to the clip view.
static inline NFBMediaTransitionRect NFBMediaOpeningImageRect(
    NFBMediaTransitionRect tile, NFBMediaTransitionRect visible, double aspect) {
  if (!isfinite(aspect) || aspect <= 0 || tile.width <= 0 || tile.height <= 0)
    return (NFBMediaTransitionRect){0, 0, visible.width, visible.height};
  double width = fmax(tile.width, tile.height * aspect), height = width / aspect;
  return (NFBMediaTransitionRect){tile.x - visible.x + (tile.width - width) / 2,
      tile.y - visible.y + (tile.height - height) / 2, width, height};
}
#endif
