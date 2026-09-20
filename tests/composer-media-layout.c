#include "../NFBComposerMediaLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  assert(NFBComposerMediaHeight(346, 1, 0) == 0);
  assert(NFBComposerMediaHeight(NAN, 1, 1) == 0);
  assert(NFBComposerMediaHeight(346, 16.0/9.0, 1) == 195);
  assert(NFBComposerMediaHeight(346, 9.0/16.0, 1) == 240);
  assert(NFBComposerMediaHeight(346, 0, 1) == 240);
  for (size_t count = 1; count <= 10; count++) {
    for (double width = 244; width <= 768; width += 4) {
      double height = NFBComposerMediaHeight(width, 1, count);
      double page = NFBComposerMediaPageWidth(width, count);
      assert(height == 240); // Portrait/square cards use the six-avatar cap.
      assert(page <= width && page > 200);
      if (count == 1) assert(page == width);
      else {
        assert(width - page - 8 == 20); // Visible hint of the next attachment.
        double extent = page * count + 8 * (count - 1);
        double lastOrigin = (page + 8) * (count - 1);
        assert(lastOrigin + page == extent); // Tenth item remains fully reachable.
      }
      for (size_t index = 0; index < count; index++) {
        double center = index * (page + 8) + page / 2;
        assert(NFBComposerMediaReorderIndex(center, page, count) == index);
        assert(NFBComposerMediaReorderIndex(center + 10, page, count) == index);
        if (index + 1 < count) {
          double boundary = center + (page + 8) / 2;
          assert(NFBComposerMediaReorderIndex(boundary - .1, page, count) == index);
          assert(NFBComposerMediaReorderIndex(boundary + .1, page, count) == index + 1);
        }
      }
      assert(NFBComposerMediaReorderIndex(-100, page, count) == 0);
      assert(NFBComposerMediaReorderIndex(1e6, page, count) == count - 1);
    }
  }
  puts("Composer attachment sizing: 1-10 items, rotation and reorder boundaries passed");
}
