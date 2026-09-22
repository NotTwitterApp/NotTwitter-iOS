#include "../NFBMediaTransitionGeometry.h"
#include <assert.h>
#include <stdio.h>
static void closeTo(double a,double b){assert(fabs(a-b)<0.00001);}
int main(void){
  // Landscape video cropped to a square: opening must not squeeze the frame.
  NFBMediaTransitionRect tile={20,100,120,120},visible=tile;
  NFBMediaTransitionRect image=NFBMediaOpeningImageRect(tile,visible,16.0/9.0);
  closeTo(image.width/image.height,16.0/9.0);closeTo(image.height,120);
  closeTo(image.x,-46.6666666667);closeTo(image.y,0);
  // Partially scrolled-off portrait thumbnail retains the same crop origin.
  tile=(NFBMediaTransitionRect){20,-30,120,120};visible=(NFBMediaTransitionRect){20,0,120,90};
  image=NFBMediaOpeningImageRect(tile,visible,0.5);
  closeTo(image.width,120);closeTo(image.height,240);closeTo(image.x,0);closeTo(image.y,-90);
  // Uncropped GIF and missing-size fallback.
  tile=(NFBMediaTransitionRect){10,100,200,100};visible=tile;
  image=NFBMediaOpeningImageRect(tile,visible,2);closeTo(image.x,0);closeTo(image.y,0);closeTo(image.width,200);
  image=NFBMediaOpeningImageRect(tile,visible,NAN);closeTo(image.width,200);closeTo(image.height,100);
  closeTo(NFBMediaOpeningDuration,0.25);
  puts("PASS: media opening crop geometry, partial visibility, aspect preservation and reference duration");
}
