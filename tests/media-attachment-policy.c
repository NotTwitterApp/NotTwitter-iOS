#include "../NFBMediaAttachmentPolicy.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  assert(NFBVideoUploadIsValid(300000000, 600));
  assert(NFBVideoUploadIsValid(100000001, 180.001)); // formerly rejected
  assert(!NFBVideoUploadIsValid(300000001, 600));
  assert(!NFBVideoUploadIsValid(300000000, 600.001));
  assert(!NFBVideoUploadIsValid(0, 30));
  assert(!NFBVideoUploadIsValid(1000, 0));
  assert(!NFBVideoUploadIsValid(1000, NAN));
  assert(!NFBVideoUploadIsValid(1000, INFINITY));
  assert(NFBMediaCountsAreValid(0, 0));
  assert(NFBMediaCountsAreValid(10, 0));
  assert(!NFBMediaCountsAreValid(11, 0));
  assert(NFBMediaCountsAreValid(0, 1));
  assert(!NFBMediaCountsAreValid(1, 1));
  assert(!NFBMediaCountsAreValid(0, 2));
  assert(!NFBMediaUsesGallery(4) && NFBMediaUsesGallery(5));
  double widths[] = {160, 240, 320, 393, 430, 768};
  size_t counts[] = {5, 10, 20};
  for (size_t w = 0; w < sizeof(widths) / sizeof(*widths); ++w) {
    for (size_t c = 0; c < sizeof(counts) / sizeof(*counts); ++c) {
      double width = widths[w]; size_t count = counts[c];
      NFBMediaCarouselGeometry g = NFBMediaCarouselLayout(width, count);
      assert(g.itemWidth > 0 && g.itemWidth < width && g.stride > g.itemWidth);
      assert(g.stride < width); // the next photo is discoverable without a swipe
      assert(NFBMediaCarouselSnapOffset(g, -100) == 0);
      assert(NFBMediaCarouselSnapOffset(g, 1e6) == g.maxOffset);
      assert(fabs(g.maxOffset + width - ((count - 1) * g.stride + g.itemWidth)) < 0.001);
      for (size_t i = 0; i < count; ++i) {
        double offset = NFBMediaCarouselSnapOffset(g, i * g.stride);
        assert(offset >= 0 && offset <= g.maxOffset);
        assert(i * g.stride >= offset - 0.001 && i * g.stride + g.itemWidth <= offset + width + 0.001);
      }
    }
  }
  assert(NFBMediaCarouselLayout(0, 10).contentWidth == 0);
  assert(NFBMediaCarouselLayout(NAN, 10).contentWidth == 0);
  assert(NFBMediaCarouselLayout(320, 0).contentWidth == 0);
  puts("Media limits, gallery boundary, and carousel reachability passed.");
}
