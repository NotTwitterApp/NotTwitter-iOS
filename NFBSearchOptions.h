#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, NFBSearchTab) {
  NFBSearchTabTop, NFBSearchTabLatest, NFBSearchTabPeople, NFBSearchTabPhotos, NFBSearchTabVideos
};
NSArray<NSString *> *NFBSearchTabTitles(void);
NSArray<NSString *> *NFBSavedSearches(void);
void NFBSetSearchSaved(NSString *query, BOOL saved);
BOOL NFBSearchHidesSensitiveContent(void);
BOOL NFBSearchExcludesMutedAccounts(void);

@interface NFBSearchOptionsViewController : UITableViewController
@property (nonatomic) BOOL followingOnly;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) void (^openSettings)(void);
@property (nonatomic, copy) void (^openAdvancedSearch)(void);
@property (nonatomic, copy) void (^applyFilters)(BOOL followingOnly);
@property (nonatomic, copy) void (^settingsChanged)(void);
- (instancetype)initWithSettings:(BOOL)settings;
@end
