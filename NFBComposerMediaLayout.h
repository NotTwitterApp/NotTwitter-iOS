#ifndef NFBComposerMediaLayout_h
#define NFBComposerMediaLayout_h
#include <math.h>
#include <stddef.h>
static inline double NFBComposerMediaHeight(double width, double aspect, size_t count) {
  if (!count || width <= 0 || !isfinite(width)) return 0;
  if (!isfinite(aspect) || aspect <= 0) aspect = 1;
  aspect = fmax(.25, fmin(4, aspect));
  // Reference maximumPreferredAttachmentsViewHeight is six 40pt avatars.
  return fmin(240, ceil(width / aspect));
}
static inline double NFBComposerMediaPageWidth(double width, size_t count) {
  return fmax(1, width - (count > 1 ? 28 : 0));
}
static inline size_t NFBComposerMediaReorderIndex(double center, double pageWidth, size_t count) {
  if (!count || !isfinite(center) || !isfinite(pageWidth) || pageWidth <= 0) return 0;
  double index = floor((center + 4) / (pageWidth + 8));
  return (size_t)fmax(0, fmin((double)count - 1, index));
}
#endif
