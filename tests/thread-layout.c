#include "../NFBThreadLayout.h"
#include <assert.h>
#include <stdio.h>

static void verify(const NFBThreadNode *nodes, size_t count, size_t anchor) {
  NFBThreadRow *rows = calloc(2 * count, sizeof(*rows));
  bool *seen = calloc(count, sizeof(bool));
  size_t length = NFBThreadBuildRows(nodes, count, anchor, rows);
  assert(length && length <= 2 * count);
  for (size_t i = 0; i < length; i++) {
    size_t node = rows[i].node;
    assert(node < count);
    if (!rows[i].gap) { assert(!seen[node]); seen[node] = true; }
    if (rows[i].above) {
      assert(i && rows[i - 1].below && !rows[i - 1].gap);
      assert(rows[i].gap ? node == rows[i - 1].node : nodes[node].parent == (ptrdiff_t)rows[i - 1].node);
    }
    if (rows[i].below) assert(i + 1 < length && rows[i + 1].above);
    if (rows[i].authorContinuation) assert(nodes[node].author && nodes[node].author == nodes[anchor].author && !nodes[node].unavailable);
  }
  assert(seen[anchor]);
  free(rows); free(seen);
}
int main(void) {
  // A -> A -> focal A -> A, then B -> A. The last A answers B and
  // must stay in B's branch, never becoming a self-thread continuation.
  NFBThreadNode nodes[] = {{-1,1,0,0},{0,1,0,0},{1,1,0,0},{2,2,0,0},{3,1,0,0},{2,1,0,0},{5,1,0,1},{2,3,0,0}};
  NFBThreadRow rows[16] = {0};
  size_t n = NFBThreadBuildRows(nodes, 8, 2, rows);
  size_t order[] = {0,1,2,5,6,6,3,4,7};
  assert(n == 9);
  for (size_t i=0;i<n;i++) assert(rows[i].node == order[i]);
  assert(rows[0].below && rows[1].above && rows[1].below && rows[2].above);
  assert(!rows[2].below && !rows[3].above);
  assert(rows[3].authorContinuation && rows[4].authorContinuation);
  assert(rows[5].gap && rows[5].above && rows[4].below);
  assert(!rows[6].above && !rows[6].authorContinuation && !rows[7].authorContinuation);
  assert(rows[6].below && rows[7].above && !rows[7].below && !rows[8].above);
  verify(nodes, 8, 2);
  // Unavailable posts retain their position but cannot bridge Reader chains.
  nodes[5].unavailable = true;
  NFBThreadBuildRows(nodes, 8, 2, rows);
  for(size_t i=0;i<n;i++) assert(!rows[i].authorContinuation);
  verify(nodes, 8, 2);
  // Separate same-author sibling branches are not joined or duplicated.
  NFBThreadNode siblings[] = {{-1,1,0,0},{0,1,0,0},{0,1,0,0},{2,1,0,0}};
  n=NFBThreadBuildRows(siblings,4,0,rows);
  assert(n==4 && rows[1].authorContinuation && !rows[2].authorContinuation && !rows[3].authorContinuation);
  assert(!rows[1].below && !rows[2].above && rows[2].below && rows[3].above);
  // Unknown identities must not be mistaken for a thread by one author.
  siblings[0].author = siblings[1].author = 0;
  verify(siblings,4,0);
  // Deterministic randomized graphs include missing parents and cycles.
  unsigned seed=42;
  for(size_t iteration=0;iteration<2000;iteration++) {
    NFBThreadNode graph[64];
    for(size_t i=0;i<64;i++) {
      seed=seed*1664525u+1013904223u;
      graph[i]=(NFBThreadNode){(ptrdiff_t)(seed%66)-1,1+(seed>>10)%4,(seed>>16)%9==0,(seed>>20)%3==0};
    }
    verify(graph,64,iteration%64);
  }
  // Long author chains are iterative, not a recursive stack overflow.
  NFBThreadNode *longThread=calloc(10000,sizeof(*longThread));
  for(size_t i=0;i<10000;i++) longThread[i]=(NFBThreadNode){(ptrdiff_t)i-1,1,0,i==9999};
  verify(longThread,10000,0);
  free(longThread);
  puts("Thread layout: author chains, branches, gaps, tombstones, 2000 malformed graphs and long threads passed.");
}
