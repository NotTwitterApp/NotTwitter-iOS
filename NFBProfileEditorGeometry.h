#ifndef NFB_PROFILE_EDITOR_GEOMETRY_H
#define NFB_PROFILE_EDITOR_GEOMETRY_H
#include <math.h>
// Twitter 9.67 T1EditProfileViewController::_setupBannerAppearance and
// scrollViewDidScroll: use these proportions in content coordinates.
static inline double NFBProfileEditorBannerHeight(double width, int landscape) { return width/(landscape ? 6.0 : 3.0); }
static inline double NFBProfileEditorAvatarScale(double offset, double bannerHeight) { return bannerHeight > 0 ? fmin(1.0,fmax(0.666,1.0-offset/(0.8*bannerHeight))) : 1.0; }
static inline double NFBProfileEditorAvatarCenterY(double bannerHeight, double avatarSize, double scale) { return bannerHeight+(0.675-0.5*scale)*avatarSize; }
#endif
