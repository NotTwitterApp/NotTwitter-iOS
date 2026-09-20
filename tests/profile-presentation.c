#include "../NFBProfilePresentation.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
  NFBProfileState state = {.hasProfile = true, .signedIn = true, .canMessage = true};
  NFBProfileElements ui = NFBProfileElementsForState(state);
  assert(ui.follow && ui.message && !ui.edit && !ui.notifications && !ui.followsYou);
  state.following = state.followsViewer = true;
  ui = NFBProfileElementsForState(state);
  assert(ui.notifications && ui.followsYou && ui.mutuals);
  state.ownProfile = true;
  ui = NFBProfileElementsForState(state);
  assert(ui.edit && ui.counts && !ui.follow && !ui.message && !ui.notifications && !ui.followsYou && !ui.mutuals);
  state.ownProfile = false;
  state.blocking = true;
  ui = NFBProfileElementsForState(state);
  assert(ui.follow && ui.counts && !ui.message && !ui.notifications && !ui.followsYou && !ui.mutuals);
  state.blocking = false;
  state.blockedBy = true;
  ui = NFBProfileElementsForState(state);
  assert(!ui.follow && !ui.message && !ui.notifications && !ui.counts && !ui.mutuals);
  state.blockedBy = false;
  state.signedIn = false;
  ui = NFBProfileElementsForState(state);
  assert(ui.follow && ui.counts && !ui.message && !ui.notifications && !ui.followsYou);
  state.signedIn = true;
  state.canMessage = false;
  assert(!NFBProfileElementsForState(state).message);
  state.hasProfile = false;
  ui = NFBProfileElementsForState(state);
  assert(!ui.edit && !ui.follow && !ui.message && !ui.notifications && !ui.counts);
  puts("Profile visibility states passed.");
}
