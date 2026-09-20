#include "../NFBGesturePolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
  assert(!NFBShouldFinishSwipe(0.1, 0, false));
  assert(NFBShouldFinishSwipe(0.5, 0, false));
  assert(NFBShouldFinishSwipe(0.05, 700, false));
  assert(!NFBShouldFinishSwipe(0.7, -600, false));
  assert(!NFBShouldFinishSwipe(0.7, 800, true));
  assert(!NFBShouldFinishSwipe(0.329, 550, false));
  assert(NFBShouldFinishSwipe(0.33, 0, false));
  puts("Swipe cancellation, reversal, distance and flick boundaries passed.");
}
