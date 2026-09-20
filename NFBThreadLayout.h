#ifndef NFBThreadLayout_h
#define NFBThreadLayout_h
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>

// Indices refer to unique post URIs. A missing author is never a self-thread match.
typedef struct {
  ptrdiff_t parent;
  size_t author;
  bool unavailable;
  bool moreReplies;
} NFBThreadNode;
typedef struct {
  size_t node;
  bool gap;
  bool ancestor;
  bool authorContinuation;
  bool above;
  bool below;
} NFBThreadRow;
typedef struct { size_t node; bool gap; bool continuation; } NFBThreadVisit;

// The caller reserves 2 * count rows. Each node appears once, followed by at
// most one expansion row. Iterative traversal also bounds malformed cycles.
static inline size_t NFBThreadBuildRows(const NFBThreadNode *nodes, size_t count,
                                        size_t anchor, NFBThreadRow *rows) {
  if (!nodes || !rows || anchor >= count) return 0;
  bool *seen = calloc(count, sizeof(bool));
  size_t *ancestors = calloc(count, sizeof(size_t));
  NFBThreadVisit *stack = calloc(count * 2 + 1, sizeof(NFBThreadVisit));
  if (!seen || !ancestors || !stack) { free(seen); free(ancestors); free(stack); return 0; }
  size_t length = 0, above = 0, pending = 0;
  seen[anchor] = true;
  ptrdiff_t parent = nodes[anchor].parent;
  while (parent >= 0 && (size_t)parent < count && !seen[parent]) {
    seen[parent] = true;
    ancestors[above++] = (size_t)parent;
    parent = nodes[parent].parent;
  }
  while (above) rows[length++] = (NFBThreadRow){.node = ancestors[--above], .ancestor = true};
  seen[anchor] = false;
  stack[pending++] = (NFBThreadVisit){anchor, false, true};
  while (pending) {
    NFBThreadVisit visit = stack[--pending];
    size_t index = visit.node;
    if (visit.gap) { rows[length++] = (NFBThreadRow){.node = index, .gap = true}; continue; }
    if (seen[index]) continue;
    seen[index] = true;
    rows[length++] = (NFBThreadRow){.node = index, .authorContinuation = index != anchor && visit.continuation};
    if (nodes[index].moreReplies && !nodes[index].unavailable)
      stack[pending++] = (NFBThreadVisit){index, true, false};
    // Keep the first same-author child with its parent. Other branches retain
    // their server order, and cannot become part of that author's reader chain.
    size_t preferred = count;
    for (size_t i = 0; i < count; i++) {
      if (nodes[i].parent == (ptrdiff_t)index && !seen[i] &&
          !nodes[index].unavailable && !nodes[i].unavailable &&
          nodes[index].author && nodes[i].author == nodes[index].author) { preferred = i; break; }
    }
    for (size_t i = count; i-- > 0;) {
      if (i != preferred && nodes[i].parent == (ptrdiff_t)index && !seen[i])
        stack[pending++] = (NFBThreadVisit){i, false, false};
    }
    if (preferred < count) stack[pending++] = (NFBThreadVisit){preferred, false, visit.continuation};
  }
  for (size_t i = 1; i < length; i++) {
    NFBThreadRow *previous = &rows[i - 1], *current = &rows[i];
    bool edge = !previous->gap && (current->gap ? current->node == previous->node :
        nodes[current->node].parent == (ptrdiff_t)previous->node);
    // The expanded focal Tweet has full-width text underneath its avatar;
    // its lower rail must not run through that text. Reply modules start anew.
    if (edge && previous->node != anchor) { previous->below = true; current->above = true; }
  }
  free(seen); free(ancestors); free(stack);
  return length;
}
#endif
