#ifndef NFBGIFRowGeometry_h
#define NFBGIFRowGeometry_h

#include <math.h>
#include <stddef.h>

typedef struct {
  size_t end;
  double height;
} NFBGIFRow;

static inline double NFBGIFAspectRatio(double ratio) {
  return isfinite(ratio) && ratio > 0 ? ratio : 1;
}

// Twitter 9.67 T1FoundMediaStreamViewController groups consecutive results
// until the fitted row is at most 150pt tall. An incomplete last row keeps
// its natural widths at 150pt, rather than stretching its GIFs to fill.
static inline NFBGIFRow NFBGIFNextRow(const double *ratios, size_t count, size_t start, double width) {
  NFBGIFRow row = { start, 0 };
  if (start >= count || !isfinite(width) || width <= 0) return row;
  double sum = 0;
  while (row.end < count) {
    sum += NFBGIFAspectRatio(ratios[row.end++]);
    double available = fmax(0, width - (row.end - start - 1));
    row.height = fmin(150, available / sum);
    if (available / sum <= 150) break;
  }
  return row;
}

#endif
