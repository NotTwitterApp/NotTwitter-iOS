#include "../NFBComposerTextLayout.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  for (unsigned kind = 1; kind <= 3; kind++) {
    bool media = kind & 1, quote = kind & 2;
    for (unsigned thread = 0; thread <= 1; thread++) {
      for (unsigned undo = 0; undo <= 1; undo++) {
        for (double line = 20.25; line <= 40; line += 3.25) {
          double previous = 0;
          // Includes wrapping, explicit newlines and a long paste over 220pt.
          for (unsigned lines = 1; lines <= 30; lines++) {
            double measured = lines * line + NFBComposerTextBottomInset(true);
            double actual = NFBComposerTextHeight(measured, line, media, quote, thread, undo);
            if (actual != ceil(lines * line)) {
              fprintf(stderr, "FAIL: %s, %u line(s): text reserves %.0fpt for %.2fpt of text\n", quote ? "quote" : "media", lines, actual, lines * line);
              return 1;
            }
            assert(actual > previous);
            previous = actual;
          }
          // Deleting to empty returns to one caret/placeholder line.
          assert(NFBComposerTextHeight(line, line, media, quote, thread, undo) == ceil(line));
          assert(NFBComposerTextHeight(0, line, media, quote, thread, undo) == ceil(line));
        }
      }
    }
  }
  assert(NFBComposerTextHeight(40, 24, false, false, false, false) == 166);
  assert(NFBComposerTextHeight(400, 24, false, false, false, false) == 220);
  puts("Composer text layout: nested content follows each line, shrinks on deletion, and expands beyond 220pt");
}
