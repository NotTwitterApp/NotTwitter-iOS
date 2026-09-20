#ifndef NFBMediaPresentationPolicy_h
#define NFBMediaPresentationPolicy_h
#include <stdbool.h>
#include <math.h>
#include <stdio.h>

static inline bool NFBMediaShowsAltBadge(bool supportsBadge, bool hasDescription,
                                         bool composer, bool obscured, bool multiPhotoQuote,
                                         bool profilePhoto) {
  return supportsBadge && !obscured && !multiPhotoQuote && !profilePhoto && (composer || hasDescription);
}
static inline bool NFBInlineAutoplayEligible(double visibleFraction, bool active,
                                             bool foreground, bool accessiblePlayback,
                                             bool obscured, bool composer, bool covered) {
  (void)active; // Reference embedded visibility threshold is 1 percent.
  return foreground && accessiblePlayback && !obscured && !composer && !covered &&
      isfinite(visibleFraction) && visibleFraction >= 0.01;
}
static inline bool NFBInlineVideoShouldLoop(bool gif, double duration) {
  return gif || (isfinite(duration) && duration > 0 && duration <= 60.0);
}
static inline bool NFBInlineVideoCanResumeEnded(double position, double duration) {
  return isfinite(position) && isfinite(duration) && position >= 0 && duration > 0 && position < duration - 0.2;
}
static inline void NFBMediaRemainingTime(double duration, double position, char *output, size_t length) {
  if (!isfinite(duration) || duration <= 0 || !isfinite(position)) { if (length) output[0] = 0; return; }
  unsigned long long seconds = (unsigned long long)ceil(fmax(0, fmin(duration, duration - position)));
  if (seconds >= 3600) snprintf(output, length, "%llu:%02llu:%02llu", seconds / 3600, seconds / 60 % 60, seconds % 60);
  else snprintf(output, length, "%llu:%02llu", seconds / 60, seconds % 60);
}
#endif
