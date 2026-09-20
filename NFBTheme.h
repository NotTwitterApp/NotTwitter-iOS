#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, NFBFontWeight) {
  NFBFontWeightRegular,
  NFBFontWeightMedium,
  NFBFontWeightBold,
  NFBFontWeightHeavy
};

// Reference TFNButton rounds the final laid-out bounds, including font changes.
@interface NFBPillButton : UIButton
@end

extern NSString * const NFBThemeDidChangeNotification;
extern NSString * const NFBDisplayModeLight;
extern NSString * const NFBDisplayModeDim;
extern NSString * const NFBDisplayModeDark;
extern NSString * const NFBTextLinkURLAttributeName;

void NFBRegisterBundledFonts(void);

NSString *NFBCurrentDisplayMode(void);
NSString *NFBPreferredDarkDisplayMode(void);
void NFBSetDisplayMode(NSString *displayMode);
UIUserInterfaceStyle NFBCurrentUserInterfaceStyle(void);
BOOL NFBStandardSiteArticlesInline(void);
void NFBSetStandardSiteArticlesInline(BOOL enabled);
BOOL NFBThreadReaderModeEnabled(void);
void NFBSetThreadReaderModeEnabled(BOOL enabled);
BOOL NFBUndoTweetEnabled(void);
void NFBSetUndoTweetEnabled(BOOL enabled);
NSInteger NFBUndoTweetIntervalSeconds(void);
void NFBSetUndoTweetIntervalSeconds(NSInteger seconds);
NSArray<NSNumber *> *NFBUndoTweetAvailableIntervals(void);
NSArray<NSString *> *NFBUndoTweetAvailableKinds(void);
BOOL NFBUndoTweetKindEnabled(NSString *kind);
void NFBSetUndoTweetKindEnabled(NSString *kind, BOOL enabled);
NSInteger NFBCurrentFontSizeLevel(void);
CGFloat NFBCurrentFontScale(void);
void NFBSetFontSizeLevel(NSInteger level);

NSInteger NFBCurrentAccentColorID(void);
UIColor *NFBAccentColorForID(NSInteger colorID);
NSString *NFBAccentColorNameForID(NSInteger colorID);
void NFBSetAccentColorID(NSInteger colorID);

typedef NS_ENUM(NSInteger, NFBIPAMetric) {
  NFBIPAMetricTimelineHorizontalInset,
  NFBIPAMetricTimelineAvatarSize,
  NFBIPAMetricTimelineAvatarTextGap,
  NFBIPAMetricTimelineTopInset,
  NFBIPAMetricTimelineContentTopInset,
  NFBIPAMetricTimelineBottomInset,
  NFBIPAMetricTimelineReasonAvatarTopInset,
  NFBIPAMetricTimelineMetaFontSize,
  NFBIPAMetricTimelineBodyFontSize,
  NFBIPAMetricTimelineActionHeight,
  NFBIPAMetricTimelineActionButtonMinWidth,
  NFBIPAMetricTimelineActionIconSize,
  NFBIPAMetricTimelineActionLabelGap,
  NFBIPAMetricVerifiedBadgeSize,
  NFBIPAMetricThreadRailWidth,
  NFBIPAMetricThreadRailAvatarGap,
  NFBIPAMetricEmbeddedCardCornerRadius,
  NFBIPAMetricEmbeddedCardInset,
  NFBIPAMetricEmbeddedCardStackSpacing,
  NFBIPAMetricEmbeddedCardAvatarSize,
  NFBIPAMetricEmbeddedCardNameFontSize,
  NFBIPAMetricEmbeddedCardBodyFontSize,
  NFBIPAMetricComposerBodyFontSize,
  NFBIPAMetricMessageBodyFontSize,
  NFBIPAMetricDetailBodyFontSize,
  NFBIPAMetricDetailFooterFontSize,
  NFBIPAMetricDetailActionButtonWidth,
  NFBIPAMetricDetailActionIconSize,
  NFBIPAMetricMediaViewerChromeIconSize,
  NFBIPAMetricMediaViewerActionIconSize
};

CGFloat NFBIPAMetricValue(NFBIPAMetric metric);

typedef NS_ENUM(NSInteger, NFBIPAColorRole) {
  NFBIPAColorRolePrimary,
  NFBIPAColorRoleText,
  NFBIPAColorRoleTextDetails,
  NFBIPAColorRoleTextPlaceholder,
  NFBIPAColorRoleBackground,
  NFBIPAColorRoleFaintBackground,
  NFBIPAColorRoleElevatedBackground,
  NFBIPAColorRoleDivider,
  NFBIPAColorRoleGroupedDivider,
  NFBIPAColorRoleDarkBackground,
  NFBIPAColorRoleHighlightOverlay,
  NFBIPAColorRoleNavigationBarShadow,
  NFBIPAColorRoleTabBarBackground,
  NFBIPAColorRoleTabBarDivider,
  NFBIPAColorRoleDashDrawerBackground,
  NFBIPAColorRoleDashDrawerText,
  NFBIPAColorRoleDashDrawerTextDetails,
  NFBIPAColorRoleDashDrawerDivider,
  NFBIPAColorRoleDashDrawerScrim,
  NFBIPAColorRoleModalSheetScrim,
  NFBIPAColorRoleModalSheetBackground,
  NFBIPAColorRoleModalSheetGrabber,
  NFBIPAColorRoleModalSheetRowHighlight,
  NFBIPAColorRoleSearchField
};

UIColor *NFBIPAColor(NFBIPAColorRole role);

typedef NS_ENUM(NSInteger, NFBIPAButtonStyle) {
  NFBIPAButtonStylePrimary,
  NFBIPAButtonStyleSecondary,
  NFBIPAButtonStyleOutline,
  NFBIPAButtonStyleNeutralOutline,
  NFBIPAButtonStyleText,
  NFBIPAButtonStyleDestructive,
  NFBIPAButtonStyleOnDarkPrimary,
  NFBIPAButtonStyleOnDarkOutline
};

typedef NS_ENUM(NSInteger, NFBIPAButtonSize) {
  NFBIPAButtonSizeCompact,
  NFBIPAButtonSizeSmall,
  NFBIPAButtonSizeMedium,
  NFBIPAButtonSizeLarge
};

UIColor *NFBColorBackground(void);
UIColor *NFBColorElevatedBackground(void);
UIColor *NFBColorText(void);
UIColor *NFBColorSecondaryText(void);
UIColor *NFBColorTertiaryText(void);
UIColor *NFBColorBorder(void);
UIColor *NFBColorAccent(void);
UIColor *NFBColorBlue(void);

UIBlurEffect *NFBIPATabBarBackgroundEffect(void);
UIColor *NFBIPADashDrawerBackgroundColor(void);
UIColor *NFBIPADashDrawerPrimaryTextColor(void);
UIColor *NFBIPADashDrawerSecondaryTextColor(void);
UIColor *NFBIPADashDrawerSeparatorColor(void);
UIColor *NFBIPADashDrawerScrimColor(void);
CGFloat NFBIPADashDrawerScrimAlpha(void);
UIColor *NFBIPAModalSheetScrimColor(void);
UIColor *NFBIPAModalSheetBackgroundColor(void);
UIColor *NFBIPAModalSheetGrabberColor(void);
UIColor *NFBIPAModalSheetRowHighlightColor(void);
CGFloat NFBIPAModalSheetBackdropAlpha(void);
CGFloat NFBIPAModalSheetCornerRadius(void);
CGFloat NFBIPAModalSheetRowHeight(void);
void NFBIPAApplyModalSheetAppearance(UIView *sheetView);
void NFBIPAApplyModalSheetGrabberAppearance(UIView *grabber);
UIColor *NFBIPATableCellSelectedBackgroundColor(void);
UIColor *NFBIPATableSeparatorColor(void);
CGFloat NFBIPATableSeparatorHeight(void);
UIColor *NFBIPAThreadRailColor(void);
UIColor *NFBIPAEmbeddedCardBorderColor(void);
void NFBIPAApplyEmbeddedCardFrameAppearance(UIView *view);
void NFBIPAApplyEmbeddedAttachmentFrameAppearance(UIView *view);
void NFBIPAApplyTableViewAppearance(UITableView *tableView);
void NFBIPAApplyTableCellAppearance(UITableViewCell *cell, UITableViewCellSelectionStyle selectionStyle);
void NFBIPAApplyTableSeparatorAppearance(UIView *separatorView);
UIColor *NFBIPASearchFieldBackgroundColor(void);
void NFBIPAApplySearchContainerAppearance(UIView *container);
void NFBIPAApplySearchTextFieldAppearance(UITextField *textField, NSString *_Nullable placeholder);
void NFBIPAApplyLegacyFormTextFieldAppearance(UITextField *textField, NSString *_Nullable placeholder, BOOL focused);
void NFBIPAApplyButtonAppearance(UIButton *button, NFBIPAButtonStyle style, NFBIPAButtonSize size);
void NFBIPAApplyFollowButtonAppearance(UIButton *button, BOOL following, BOOL destructive, BOOL overDarkBackground);
UIColor *NFBIPAMessageOutgoingBubbleColor(void);
UIColor *NFBIPAMessageIncomingBubbleColor(void);
UIColor *NFBIPAMessageInputBackgroundColor(void);
void NFBIPAApplyMessageInputContainerAppearance(UIView *container);
void NFBIPAApplyMessageBubbleAppearance(UIView *bubbleView, BOOL outgoing);
void NFBIPAApplyMessageReactionPillAppearance(UILabel *reactionLabel);
void NFBIPAApplyMessageReactionTrayAppearance(UIView *trayView);
void NFBIPAApplyMessageSendButtonAppearance(UIButton *button, BOOL active);
BOOL NFBIPAProfileFollowsViewer(NSDictionary *_Nullable profile);
void NFBIPAApplyFollowsYouBadgeAppearance(UILabel *label);
UIColor *NFBIPAOnMediaBarBackgroundColor(void);
UIColor *NFBIPAOnMediaSeparatorColor(void);
UIColor *NFBIPAOnMediaPrimaryTextColor(void);
UIColor *NFBIPAOnMediaSecondaryTextColor(void);
UIColor *NFBIPAOnMediaMutedTextColor(void);
void NFBIPAApplyOnMediaBarAppearance(UIView *barView);
void NFBIPAApplyOnMediaSeparatorAppearance(UIView *separatorView);
void NFBIPAApplyOnMediaIconButtonAppearance(UIButton *button, BOOL selected, CGFloat cornerRadius);
void NFBIPAApplyOnMediaFloatingButtonAppearance(UIButton *button, CGFloat cornerRadius);
void NFBIPAApplyOnMediaLabelPillAppearance(UILabel *label, CGFloat cornerRadius);

UIFont *NFBFont(CGFloat size, NFBFontWeight weight);
NSString *NFBShortCountString(NSInteger count);
NSAttributedString *NFBTweetBodyAttributedString(NSString *_Nullable text, UIFont *font);
NSAttributedString *NFBTweetBodyAttributedStringForPost(NSDictionary *_Nullable post, UIFont *font);
NSAttributedString *NFBComposerTextAttributedString(NSString *_Nullable text, UIFont *font);
UIImage *_Nullable NFBTwemojiImageForEmoji(NSString *emoji);
NSAttributedString *NFBAttributedStringByReplacingEmojiWithTwemoji(NSAttributedString *attributed, UIFont *font);
UIImage *_Nullable NFBTemplateIcon(NSString *name);
UIImage *_Nullable NFBBundledImage(NSString *directory, NSString *name, NSString *extension);
UIImage *_Nullable NFBVerifiedBadgeImage(void);
UIImage *_Nullable NFBDefaultAvatarImage(void);
UIImage *_Nullable NFBDefaultCoverImage(void);
UIImage *_Nullable NFBBrandIconImage(void);
UIImage *_Nullable NFBLoadingImage(void);
UIRefreshControl *NFBCreateRefreshControl(id target, SEL action);
void NFBUpdateRefreshControlAppearance(UIRefreshControl *refreshControl);
UIView *NFBTitleView(NSString *title, NSString *_Nullable subtitle);
UIBarButtonItem *NFBBackBarButtonItem(id target, SEL action);
void NFBStartLoadingAnimation(UIImageView *imageView);
void NFBStopLoadingAnimation(UIImageView *imageView);
void NFBPlaySound(NSString *fileName);
void NFBApplyTombstoneAppearance(UIView *container, UILabel *titleLabel, UILabel *subtitleLabel, CGFloat titleSize, CGFloat subtitleSize);
void NFBApplyFramedTombstoneAppearance(UIView *container, UILabel *titleLabel, UILabel *subtitleLabel, CGFloat titleSize, CGFloat subtitleSize);

void NFBApplyAppAppearance(UIWindow *window);
void NFBApplyNavigationAppearance(UINavigationController *navigationController);
void NFBApplyDarkNavigationAppearance(UINavigationController *navigationController);
void NFBApplyTabBarAppearance(UITabBar *tabBar);
void NFBApplyThemeToVisibleWindows(void);

@interface NFBInteractiveTextLabel : UILabel

@property (nonatomic, copy, nullable) void (^linkTapHandler)(NSURL *url);
@property (nonatomic, copy, nullable) void (^plainTapHandler)(void);

@end

NS_ASSUME_NONNULL_END
