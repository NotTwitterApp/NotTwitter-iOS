#include <assert.h>
#include <stdio.h>
#include "../NFBProfileEditorGeometry.h"
int main(void) {
  assert(NFBProfileEditorBannerHeight(390,0)==130);
  assert(NFBProfileEditorBannerHeight(780,1)==130);
  assert(NFBProfileEditorAvatarScale(-100,130)==1);
  assert(fabs(NFBProfileEditorAvatarCenterY(130,80,1)-144)<0.001);
  for (int y=0;y<600;y++) {
    double s=NFBProfileEditorAvatarScale(y,130);
    assert(s>=0.666 && s<=1);
    assert(s<=NFBProfileEditorAvatarScale(y-1,130));
    assert(isfinite(NFBProfileEditorAvatarCenterY(130,80,s)));
  }
  assert(NFBProfileEditorAvatarScale(400,130)==0.666);
  assert(isfinite(NFBProfileEditorAvatarScale(400,0)));
  puts("PASS: portrait/landscape reference banner ratio, avatar overlap, pull-down and collapse bounds");
}
