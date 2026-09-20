#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@interface NFBMediaLibraryViewController : UIViewController
@property (nonatomic, assign) NSUInteger photoLimit;
@property (nonatomic, assign) BOOL allowsVideo;
@property (nonatomic, copy) void (^selectionHandler)(NSArray<PHAsset *> *assets);
@property (nonatomic, copy) void (^cameraHandler)(BOOL video);
@end
