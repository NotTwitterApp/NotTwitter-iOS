#include "../NFBChromeGeometry.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
 assert(NFBHeaderCollapse(0,20,44,80,true)==20);
 assert(NFBHeaderCollapse(20,50,44,100,true)==44);
 assert(NFBHeaderCollapse(44,-10,44,100,true)==34);
 assert(NFBHeaderCollapse(34,-60,44,80,true)==0);
 assert(NFBHeaderCollapse(44,20,44,-1,true)==0);
 assert(NFBHeaderCollapse(44,20,44,100,false)==0);
 assert(NFBHeaderSettledCollapse(20,44,0)==0);
 assert(NFBHeaderSettledCollapse(24,44,0)==44);
 assert(NFBHeaderSettledCollapse(2,44,200)==44);
 assert(NFBHeaderSettledCollapse(42,44,-200)==0);
 assert(NFBTabBarHeight(34,false)==86);
 assert(NFBTabBarHeight(0,false)==52);
 assert(NFBTabBarHeight(21,true)==53);
 puts("PASS: collapse, direction reversal, top bounce, short feeds, settling and tab-bar safe areas");
}
