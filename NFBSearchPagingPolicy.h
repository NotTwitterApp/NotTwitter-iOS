#pragma once
#include <math.h>
#include <stdbool.h>

static inline long NFBSearchPageForOffset(double offset, double width, long count) {
  if (width <= 0 || count <= 0 || !isfinite(width) || !isfinite(offset)) return 0;
  return (long)fmin(count - 1, fmax(0, floor(offset / width)));
}
// The reference truncates offset/pageWidth while tracking. At rest UIKit lands
// on a page boundary; rounding tolerates subpixel layout noise at that boundary.
static inline long NFBSearchSettledPageForOffset(double offset, double width, long count) {
  if (width <= 0 || count <= 0 || !isfinite(width) || !isfinite(offset)) return 0;
  return (long)fmin(count - 1, fmax(0, floor(offset / width + 0.5)));
}
static inline bool NFBSearchPagingHasDestination(long page, long count, double velocityX) {
  return count > 1 && page >= 0 && page < count && ((velocityX < 0 && page < count - 1) || (velocityX > 0 && page > 0));
}
// TFNPagingScrollView::_tfn_panGestureRecognizerShouldBegin, Twitter 9.67:
// both outer extents fail; within the range, require |vx| > 2 * |vy|.
static inline bool NFBSearchPagingShouldBegin(long page, long count, double velocityX, double velocityY) {
  return NFBSearchPagingHasDestination(page, count, velocityX) && fabs(velocityX) > 2 * fabs(velocityY);
}
