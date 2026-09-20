#import <UIKit/UIKit.h>

// Retains the gesture with the sheet, but never retains its controller.
void NFBInstallSheetDismissGesture(UIView *sheet, UIView *backdrop, id target, SEL cancelAction);
void NFBInstallComposerDismissGesture(UIView *composer, id target, SEL cancelAction);
