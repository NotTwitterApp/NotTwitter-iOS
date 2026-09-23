#ifndef NFBChromeGeometry_h
#define NFBChromeGeometry_h
#include <math.h>
#include <stdbool.h>

// Offset-based collapse mirrors the reference's navigationBarExpansionRatio.
static inline double NFBHeaderCollapse(double previous, double scrollDelta, double height, double topOffset, bool scrollable) {
  if (!scrollable || topOffset <= 0 || height <= 0) return 0;
  return fmax(0, fmin(height, previous + scrollDelta));
}
static inline double NFBHeaderSettledCollapse(double collapse, double height, double velocity) {
  if (velocity > 100) return height;
  if (velocity < -100) return 0;
  return collapse >= height * 0.5 ? height : 0;
}
// Screenshot target: 52pt control area with the device's home-indicator inset.
static inline double NFBTabBarHeight(double bottomInset, bool compact) {
  return (compact ? 32.0 : 52.0) + fmax(0, bottomInset);
}
#endif
