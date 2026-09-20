#import <UIKit/UIKit.h>

// Shared by the account picker, drawer, and tab headers so a selected account's
// already-visible photo is available synchronously during the screen transition.
void NFBLoadAccountAvatar(UIImageView *imageView, NSString *urlString);
