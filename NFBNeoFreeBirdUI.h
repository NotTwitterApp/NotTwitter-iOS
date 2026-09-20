#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NFBNeoFreeBirdTabDefinition : NSObject

@property (nonatomic, copy, readonly) NSString *pageID;
@property (nonatomic, copy, readonly) NSString *title;
@property (nonatomic, copy, readonly) NSString *iconName;
@property (nonatomic, copy, readonly) NSString *selectedIconName;

- (instancetype)initWithPageID:(NSString *)pageID
                         title:(NSString *)title
                      iconName:(NSString *)iconName
              selectedIconName:(NSString *)selectedIconName;

@end

void NFBApplyNeoFreeBirdFirstRunDefaults(void);
UIColor *NFBNeoFreeBirdAccentColor(void);
UIColor *NFBNeoFreeBirdTabBarSelectedTintColor(void);
UIColor *NFBNeoFreeBirdTabBarNormalTintColor(void);
BOOL NFBNeoFreeBirdRestoreTabLabels(void);
BOOL NFBNeoFreeBirdColorTopBirdIcon(void);
BOOL NFBNeoFreeBirdHideViewCount(void);
NSArray<NFBNeoFreeBirdTabDefinition *> *NFBNeoFreeBirdVisibleTabDefinitions(void);
void NFBPresentNeoFreeBirdRetweetSheet(UIViewController *presenter,
                                       BOOL reposted,
                                       dispatch_block_t _Nullable retweetHandler,
                                       dispatch_block_t _Nullable quoteHandler);
void NFBPresentNeoFreeBirdActionSheet(UIViewController *presenter,
                                      NSArray<NSDictionary<NSString *, id> *> *actions,
                                      NSString *_Nullable cancelTitle);
void NFBPresentNeoFreeBirdMenuSheet(UIViewController *presenter,
                                    NSString *_Nullable title,
                                    NSString *_Nullable subtitle,
                                    NSArray<NSDictionary<NSString *, id> *> *actions,
                                    NSString *_Nullable cancelTitle);

NS_ASSUME_NONNULL_END
