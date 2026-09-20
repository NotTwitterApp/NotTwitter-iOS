#ifndef NFBComposerTextLayout_h
#define NFBComposerTextLayout_h
#include <math.h>
#include <stdbool.h>

static inline double NFBComposerTextBottomInset(bool hasNestedContent) {
  return hasNestedContent ? 0 : 18;
}

// measured includes UITextView's textContainerInset and its trailing caret line.
static inline double NFBComposerTextHeight(double measured, double lineHeight,
    bool hasMedia, bool hasQuote, bool hasThreadRows, bool undoPending) {
  if (hasMedia || hasQuote) return ceil(fmax(lineHeight, measured));
  if (undoPending) return ceil(measured);
  double minimum = hasThreadRows ? 64 : 166;
  return fmin(220, fmax(minimum, ceil(measured)));
}
#endif
