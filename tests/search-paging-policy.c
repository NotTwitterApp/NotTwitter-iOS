#include "../NFBSearchPagingPolicy.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
  // The reference uses a strict 2:1 gate, not a generic flick or 45-degree gate.
  assert(!NFBSearchPagingShouldBegin(2, 5, 400, 200));
  assert(NFBSearchPagingShouldBegin(2, 5, 400.01, 200));
  assert(NFBSearchPagingShouldBegin(2, 5, -400.01, -200));
  assert(!NFBSearchPagingShouldBegin(2, 5, 199, 100));
  assert(!NFBSearchPagingShouldBegin(2, 5, 0, 0));
  // Both outer extents yield; no wrap from Top to Videos or vice versa.
  assert(!NFBSearchPagingShouldBegin(0, 5, 900, 0));
  assert(NFBSearchPagingShouldBegin(0, 5, -900, 0));
  assert(!NFBSearchPagingShouldBegin(4, 5, -900, 0));
  assert(NFBSearchPagingShouldBegin(4, 5, 900, 0));
  assert(!NFBSearchPagingShouldBegin(0, 1, -900, 0));
  assert(!NFBSearchPagingShouldBegin(0, 0, 900, 0));
  assert(NFBSearchPageForOffset(299, 300, 5) == 0);
  assert(NFBSearchPageForOffset(300, 300, 5) == 1);
  assert(NFBSearchPageForOffset(599, 300, 5) == 1);
  assert(NFBSearchPageForOffset(-40, 300, 5) == 0);
  assert(NFBSearchPageForOffset(1600, 300, 5) == 4);
  assert(NFBSearchPageForOffset(300, 0, 5) == 0);
  assert(NFBSearchPageForOffset(NAN, 300, 5) == 0);
  assert(NFBSearchSettledPageForOffset(599.999, 300, 5) == 2);
  assert(NFBSearchSettledPageForOffset(0, 428, 5) == 0);
  assert(NFBSearchSettledPageForOffset(1712, 428, 5) == 4);
  puts("PASS: reference 2:1 gate, outer edges, tracking index, settled index, resize/overscroll bounds");
}
