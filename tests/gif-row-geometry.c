#include "../NFBGIFRowGeometry.h"
#include <assert.h>
#include <stdio.h>

static void fits(const double *ratios, size_t count, double width) {
  size_t start = 0;
  while (start < count) {
    NFBGIFRow row = NFBGIFNextRow(ratios, count, start, width);
    assert(row.end > start && row.end <= count);
    assert(row.height > 0 && row.height <= 150);
    double used = row.end - start - 1;
    for (size_t i = start; i < row.end; i++) used += NFBGIFAspectRatio(ratios[i]) * row.height;
    assert(used <= width + 0.0001);
    // Completed rows fill the available width; only the final row can be short.
    if (row.end < count) assert(fabs(used - width) < 0.0001);
    start = row.end;
  }
}

int main(void) {
  double squares[] = {1, 1, 1, 1};
  NFBGIFRow row = NFBGIFNextRow(squares, 4, 0, 393);
  assert(row.end == 3 && fabs(row.height - 391.0 / 3) < 0.0001);
  row = NFBGIFNextRow(squares, 4, 3, 393);
  assert(row.end == 4 && row.height == 150);
  double mixed[] = {0.5, 2, 1.777, 0.75, 1, 3, 0.2, 0.8, 1.3, 2};
  double widths[] = {320, 375, 393, 430, 844};
  for (size_t i = 0; i < sizeof(widths) / sizeof(*widths); i++) fits(mixed, 10, widths[i]);
  double malformed[] = {0, NAN, INFINITY, -1};
  fits(malformed, 4, 393);
  assert(NFBGIFNextRow(NULL, 0, 0, 393).end == 0);
  assert(NFBGIFNextRow(squares, 4, 0, 0).height == 0);
  puts("GIF row geometry passed: ordering, aspect ratios, full/partial rows, narrow/landscape widths, invalid dimensions.");
}
