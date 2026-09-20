#ifndef NFB_MEDIA_ATTACHMENT_POLICY_H
#define NFB_MEDIA_ATTACHMENT_POLICY_H
#include <stdbool.h>
#include <stddef.h>
#include <math.h>

// Bluesky authoring limits, verified against social-app/constants.ts and embed lexicons.
enum { NFBMaxImageUploadBytes = 2000000, NFBMaxVideoUploadBytes = 300000000, NFBMaxImageDimension = 4000 };
static const double NFBMaxVideoDuration = 600.0;
static inline bool NFBVideoUploadIsValid(size_t bytes, double seconds) {
  return bytes > 0 && bytes <= NFBMaxVideoUploadBytes && isfinite(seconds) && seconds > 0 && seconds <= NFBMaxVideoDuration;
}
enum { NFBMaxPhotosPerPost = 10, NFBLegacyPhotoGridLimit = 4 };
static inline bool NFBMediaUsesGallery(size_t count) { return count > NFBLegacyPhotoGridLimit; }
static inline bool NFBMediaCountsAreValid(size_t photos, size_t videos) {
  return photos <= NFBMaxPhotosPerPost && videos <= 1 && !(photos && videos);
}

typedef struct { double itemWidth, stride, contentWidth, maxOffset; } NFBMediaCarouselGeometry;
static inline NFBMediaCarouselGeometry NFBMediaCarouselLayout(double width, size_t count) {
  if (!isfinite(width) || width <= 0 || count == 0) return (NFBMediaCarouselGeometry){0};
  double item = fmax(1, width - fmin(24, width * 0.12));
  double stride = item + 4;
  double content = count * stride - 4;
  return (NFBMediaCarouselGeometry){item, stride, content, fmax(0, content - width)};
}
static inline double NFBMediaCarouselSnapOffset(NFBMediaCarouselGeometry layout, double proposed) {
  if (layout.stride <= 0 || !isfinite(proposed)) return 0;
  return fmin(layout.maxOffset, fmax(0, round(proposed / layout.stride) * layout.stride));
}
#endif
