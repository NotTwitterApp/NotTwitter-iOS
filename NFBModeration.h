#import <Foundation/Foundation.h>

@class UIFont;

NS_ASSUME_NONNULL_BEGIN

extern NSString * const NFBModerationPreferencesDidChangeNotification;
extern NSString * const NFBModerationTombstoneLearnMoreURLString;
extern NSString * const NFBModerationTombstoneRulesURLString;

void NFBModerationRefreshPreferencesIfNeeded(void);
void NFBModerationCachePreferences(NSArray<NSDictionary *> *preferences);
NSDictionary *_Nullable NFBModerationTombstoneForFeedItem(NSDictionary *_Nullable feedItem, NSDictionary *_Nullable post);
NSDictionary *_Nullable NFBModerationMediaWarningForPost(NSDictionary *_Nullable post);
NSArray<NSDictionary *> *NFBModerationMediaItemsByApplyingWarnings(NSArray<NSDictionary *> *mediaItems, NSDictionary *_Nullable post);
NSAttributedString *NFBModerationTombstoneAttributedString(NSDictionary *_Nullable tombstone, UIFont *_Nullable font);

NS_ASSUME_NONNULL_END
