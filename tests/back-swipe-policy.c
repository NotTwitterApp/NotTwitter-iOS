#include "../NFBGesturePolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
  assert(NFBBackSwipeShouldBegin(200, 200));
  assert(NFBBackSwipeShouldBegin(200, -200));
  assert(!NFBBackSwipeShouldBegin(200, 200.01));
  assert(!NFBBackSwipeShouldBegin(0, 0));
  assert(!NFBBackSwipeShouldBegin(-300, 0));
  assert(!NFBBackSwipeShouldFinish(.5999, 199.99, false));
  assert(NFBBackSwipeShouldFinish(.6, 0, false));
  assert(NFBBackSwipeShouldFinish(.05, 200, false));
  assert(NFBBackSwipeShouldFinish(.6, -200, false));
  assert(!NFBBackSwipeShouldFinish(.9, -200.01, false));
  assert(!NFBBackSwipeShouldFinish(.9, 500, true));
  assert(!NFBBackSwipeShouldFinish(NAN, 500, false));
  puts("PASS: reference back-swipe angle, 60% distance, 200 pt/s flick, reversal and cancellation boundaries");
}
