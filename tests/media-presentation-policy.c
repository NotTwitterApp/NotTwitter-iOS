#include "../NFBMediaPresentationPolicy.h"
#include <assert.h>
#include <string.h>
int main(void) {
  assert(NFBMediaShowsAltBadge(true,true,false,false,false,false));
  assert(!NFBMediaShowsAltBadge(true,false,false,false,false,false));
  assert(!NFBMediaShowsAltBadge(false,true,false,false,false,false)); // video/GIF consumption
  assert(NFBMediaShowsAltBadge(true,false,true,false,false,false)); // composer description editor
  assert(!NFBMediaShowsAltBadge(true,true,false,true,false,false)); // concealed media
  assert(!NFBMediaShowsAltBadge(true,true,false,false,false,true)); // profile image
  assert(NFBInlineAutoplayEligible(.01,false,true,true,false,false,false));
  assert(!NFBInlineAutoplayEligible(.009,false,true,true,false,false,false));
  assert(!NFBInlineAutoplayEligible(1,true,false,true,false,false,false));
  assert(!NFBInlineAutoplayEligible(1,true,true,false,false,false,false));
  assert(!NFBInlineAutoplayEligible(1,true,true,true,true,false,false));
  assert(!NFBInlineAutoplayEligible(1,true,true,true,false,true,false));
  assert(!NFBInlineAutoplayEligible(1,true,true,true,false,false,true));
  assert(!NFBInlineAutoplayEligible(NAN,true,true,true,false,false,false));
  assert(NFBInlineVideoShouldLoop(false,60));
  assert(!NFBInlineVideoShouldLoop(false,60.01));
  assert(!NFBInlineVideoShouldLoop(false,NAN));
  assert(!NFBInlineVideoShouldLoop(false,0));
  assert(NFBInlineVideoShouldLoop(true,120));
  assert(NFBInlineVideoCanResumeEnded(0,120));
  assert(NFBInlineVideoCanResumeEnded(50,120));
  assert(!NFBInlineVideoCanResumeEnded(120,120));
  assert(!NFBInlineVideoCanResumeEnded(119.9,120));
  assert(!NFBInlineVideoCanResumeEnded(0,0));
  assert(!NFBInlineVideoCanResumeEnded(NAN,120));
  char text[32];
  NFBMediaRemainingTime(61.2,0,text,sizeof(text)); assert(!strcmp(text,"1:02"));
  NFBMediaRemainingTime(61.2,1.3,text,sizeof(text)); assert(!strcmp(text,"1:00"));
  NFBMediaRemainingTime(61.2,60.4,text,sizeof(text)); assert(!strcmp(text,"0:01"));
  NFBMediaRemainingTime(61.2,100,text,sizeof(text)); assert(!strcmp(text,"0:00"));
  NFBMediaRemainingTime(3661,0,text,sizeof(text)); assert(!strcmp(text,"1:01:01"));
  NFBMediaRemainingTime(INFINITY,0,text,sizeof(text)); assert(!text[0]);
  NFBMediaRemainingTime(NAN,0,text,sizeof(text)); assert(!text[0]);
  puts("Media policies: ALT visibility, autoplay/loop boundaries, fullscreen resume and remaining-time formatting passed.");
}
