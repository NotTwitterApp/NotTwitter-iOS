#import "NFBRichText.h"
#import "NFBPostLinkResolver.h"
#import "NFBTheme.h"

#import "NFBNeoFreeBirdUI.h"

#import <AudioToolbox/AudioToolbox.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

NSString * const NFBThemeDidChangeNotification = @"NFBThemeDidChangeNotification";
NSString * const NFBDisplayModeLight = @"light";
NSString * const NFBDisplayModeDim = @"dim";
NSString * const NFBDisplayModeDark = @"dark";
NSString * const NFBTextLinkURLAttributeName = @"NFBTextLinkURLAttributeName";

static NSString * const NFBDisplayModePreferenceKey = @"nfb_display_mode";
static NSString * const NFBDisplayModeLastDarkPreferenceKey = @"nfb_display_mode_last_dark";
static NSString * const NFBStandardSiteArticlesInlinePreferenceKey = @"nfb_standard_site_articles_inline";
static NSString * const NFBThreadReaderModePreferenceKey = @"nfb_thread_reader_mode";
static NSString * const NFBUndoTweetEnabledPreferenceKey = @"nfb_undo_tweet_enabled";
static NSString * const NFBUndoTweetIntervalPreferenceKey = @"nfb_undo_tweet_interval_seconds";
static NSString * const NFBUndoTweetKindEnabledPrefix = @"nfb_undo_tweet_kind_enabled_";
static NSString * const NFBFontSizeLevelPreferenceKey = @"nfb_font_size_level";
static NSString * const NFBColorThemeSelectedKey = @"bh_color_theme_selectedColor";
static NSString * const NFBColorThemeLastSelectedKey = @"bh_last_selected_color_theme";
static NSString * const NFBTwitterPrimaryColorOptionKey = @"T1ColorSettingsPrimaryColorOptionKey";
static CGFloat const NFBFontSizeScales[] = {0.90, 0.96, 1.0, 1.08, 1.16};
static NSInteger const NFBFontSizeLevelCount = 5;

static UIColor *NFBColorFromHex(NSUInteger rgb) {
  return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0
                         green:((rgb >> 8) & 0xff) / 255.0
                          blue:(rgb & 0xff) / 255.0
                         alpha:1.0];
}

static BOOL NFBDisplayModeIsValid(NSString *displayMode);

static NSString *NFBIPAResolvedDisplayMode(void) {
  NSString *mode = NFBCurrentDisplayMode();
  return NFBDisplayModeIsValid(mode) ? mode : NFBDisplayModeDark;
}

static BOOL NFBDisplayModeIsValid(NSString *displayMode) {
  return [displayMode isEqualToString:NFBDisplayModeLight] ||
         [displayMode isEqualToString:NFBDisplayModeDim] ||
         [displayMode isEqualToString:NFBDisplayModeDark];
}

static NSDictionary *NFBHiddenTabTitleAttributes(void) {
  return @{
    NSForegroundColorAttributeName: UIColor.clearColor,
    NSFontAttributeName: [UIFont systemFontOfSize:0.1]
  };
}

static UIBlurEffectStyle NFBTabBarBlurEffectStyle(void) {
  if ([NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight]) return UIBlurEffectStyleSystemChromeMaterialLight;
  return UIBlurEffectStyleSystemChromeMaterialDark;
}

static void NFBConfigureTabBarItemAppearance(UITabBarItemAppearance *itemAppearance) {
  itemAppearance.normal.iconColor = NFBNeoFreeBirdTabBarNormalTintColor();
  itemAppearance.normal.titleTextAttributes = NFBHiddenTabTitleAttributes();
  itemAppearance.selected.iconColor = NFBNeoFreeBirdTabBarSelectedTintColor();
  itemAppearance.selected.titleTextAttributes = NFBHiddenTabTitleAttributes();
}

static UITabBarAppearance *NFBConfiguredTabBarAppearance(void) {
  UITabBarAppearance *appearance = [[UITabBarAppearance alloc] init];
  [appearance configureWithOpaqueBackground];
  if ([appearance respondsToSelector:@selector(setBackgroundEffect:)]) {
    appearance.backgroundEffect = nil;
  }
  appearance.backgroundColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);
  appearance.shadowColor = UIColor.clearColor; // Draw one physical pixel in the controller.
  appearance.stackedItemPositioning = UITabBarItemPositioningFill;
  appearance.stackedItemSpacing = 0;
  NFBConfigureTabBarItemAppearance(appearance.stackedLayoutAppearance);
  NFBConfigureTabBarItemAppearance(appearance.inlineLayoutAppearance);
  NFBConfigureTabBarItemAppearance(appearance.compactInlineLayoutAppearance);
  return appearance;
}

void NFBRegisterBundledFonts(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSArray<NSString *> *fontFiles = @[
      @"Chirp-Regular.otf",
      @"Chirp-Medium.otf",
      @"Chirp-Bold.otf",
      @"Chirp-Heavy.otf",
      @"Chirp-UI-VF.ttf",
      @"ChirpCY-Regular.otf",
      @"ChirpCY-Medium.otf",
      @"ChirpCY-Bold.otf",
      @"ChirpCY-Heavy.otf"
    ];
    for (NSString *fontFile in fontFiles) {
      NSURL *url = [[NSBundle mainBundle] URLForResource:[fontFile stringByDeletingPathExtension]
                                           withExtension:fontFile.pathExtension
                                            subdirectory:@"Chirp"];
      if (!url) continue;
      CFErrorRef error = NULL;
      CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, &error);
      if (error) CFRelease(error);
    }
  });
}

NSString *NFBCurrentDisplayMode(void) {
  NSString *displayMode = [NSUserDefaults.standardUserDefaults stringForKey:NFBDisplayModePreferenceKey];
  return NFBDisplayModeIsValid(displayMode) ? displayMode : NFBDisplayModeDark;
}

NSString *NFBPreferredDarkDisplayMode(void) {
  NSString *displayMode = [NSUserDefaults.standardUserDefaults stringForKey:NFBDisplayModeLastDarkPreferenceKey];
  if ([displayMode isEqualToString:NFBDisplayModeDim] || [displayMode isEqualToString:NFBDisplayModeDark]) return displayMode;
  displayMode = [NSUserDefaults.standardUserDefaults stringForKey:NFBDisplayModePreferenceKey];
  if ([displayMode isEqualToString:NFBDisplayModeDim] || [displayMode isEqualToString:NFBDisplayModeDark]) return displayMode;
  return NFBDisplayModeDark;
}

void NFBSetDisplayMode(NSString *displayMode) {
  if (!NFBDisplayModeIsValid(displayMode)) displayMode = NFBDisplayModeDark;
  if (![displayMode isEqualToString:NFBDisplayModeLight]) {
    [NSUserDefaults.standardUserDefaults setObject:displayMode forKey:NFBDisplayModeLastDarkPreferenceKey];
  }
  [NSUserDefaults.standardUserDefaults setObject:displayMode forKey:NFBDisplayModePreferenceKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  NFBApplyThemeToVisibleWindows();
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

UIUserInterfaceStyle NFBCurrentUserInterfaceStyle(void) {
  return [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? UIUserInterfaceStyleLight : UIUserInterfaceStyleDark;
}

BOOL NFBStandardSiteArticlesInline(void) {
  return [NSUserDefaults.standardUserDefaults boolForKey:NFBStandardSiteArticlesInlinePreferenceKey];
}

void NFBSetStandardSiteArticlesInline(BOOL enabled) {
  [NSUserDefaults.standardUserDefaults setBool:enabled forKey:NFBStandardSiteArticlesInlinePreferenceKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

BOOL NFBThreadReaderModeEnabled(void) {
  return [NSUserDefaults.standardUserDefaults boolForKey:NFBThreadReaderModePreferenceKey];
}

void NFBSetThreadReaderModeEnabled(BOOL enabled) {
  [NSUserDefaults.standardUserDefaults setBool:enabled forKey:NFBThreadReaderModePreferenceKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

NSArray<NSNumber *> *NFBUndoTweetAvailableIntervals(void) {
  return @[@5, @10, @20, @30, @60];
}

NSArray<NSString *> *NFBUndoTweetAvailableKinds(void) {
  return @[@"tweet", @"reply", @"quote", @"thread"];
}

static BOOL NFBUndoTweetKindIsValid(NSString *kind) {
  for (NSString *candidate in NFBUndoTweetAvailableKinds()) {
    if ([candidate isEqualToString:kind]) return YES;
  }
  return NO;
}

BOOL NFBUndoTweetEnabled(void) {
  return [NSUserDefaults.standardUserDefaults boolForKey:NFBUndoTweetEnabledPreferenceKey];
}

void NFBSetUndoTweetEnabled(BOOL enabled) {
  [NSUserDefaults.standardUserDefaults setBool:enabled forKey:NFBUndoTweetEnabledPreferenceKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

NSInteger NFBUndoTweetIntervalSeconds(void) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSInteger interval = [defaults objectForKey:NFBUndoTweetIntervalPreferenceKey]
    ? [defaults integerForKey:NFBUndoTweetIntervalPreferenceKey]
    : 20;
  for (NSNumber *candidate in NFBUndoTweetAvailableIntervals()) {
    if (candidate.integerValue == interval) return interval;
  }
  return 20;
}

void NFBSetUndoTweetIntervalSeconds(NSInteger seconds) {
  BOOL valid = NO;
  for (NSNumber *candidate in NFBUndoTweetAvailableIntervals()) {
    if (candidate.integerValue == seconds) {
      valid = YES;
      break;
    }
  }
  [NSUserDefaults.standardUserDefaults setInteger:(valid ? seconds : 20) forKey:NFBUndoTweetIntervalPreferenceKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

BOOL NFBUndoTweetKindEnabled(NSString *kind) {
  if (!NFBUndoTweetKindIsValid(kind)) return YES;
  NSString *key = [NFBUndoTweetKindEnabledPrefix stringByAppendingString:kind];
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  return [defaults objectForKey:key] ? [defaults boolForKey:key] : YES;
}

void NFBSetUndoTweetKindEnabled(NSString *kind, BOOL enabled) {
  if (!NFBUndoTweetKindIsValid(kind)) return;
  NSString *key = [NFBUndoTweetKindEnabledPrefix stringByAppendingString:kind];
  [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

NSInteger NFBCurrentFontSizeLevel(void) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSInteger level = [defaults objectForKey:NFBFontSizeLevelPreferenceKey] ? [defaults integerForKey:NFBFontSizeLevelPreferenceKey] : 2;
  if (level < 0) return 0;
  if (level >= NFBFontSizeLevelCount) return NFBFontSizeLevelCount - 1;
  return level;
}

CGFloat NFBCurrentFontScale(void) {
  return NFBFontSizeScales[NFBCurrentFontSizeLevel()];
}

void NFBSetFontSizeLevel(NSInteger level) {
  if (level < 0) level = 0;
  if (level >= NFBFontSizeLevelCount) level = NFBFontSizeLevelCount - 1;
  [NSUserDefaults.standardUserDefaults setInteger:level forKey:NFBFontSizeLevelPreferenceKey];
  [NSUserDefaults.standardUserDefaults synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

NSInteger NFBCurrentAccentColorID(void) {
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  NSInteger colorID = 1;
  if ([defaults objectForKey:NFBColorThemeSelectedKey]) {
    colorID = [defaults integerForKey:NFBColorThemeSelectedKey];
  } else if ([defaults objectForKey:NFBTwitterPrimaryColorOptionKey]) {
    colorID = [defaults integerForKey:NFBTwitterPrimaryColorOptionKey];
  }
  return colorID >= 1 && colorID <= 6 ? colorID : 1;
}

UIColor *NFBAccentColorForID(NSInteger colorID) {
  switch (colorID) {
    case 1: return NFBColorFromHex(0x1d9bf0);
    case 2: return NFBColorFromHex(0xffd400);
    case 3: return NFBColorFromHex(0xf91880);
    case 4: return NFBColorFromHex(0x7856ff);
    case 5: return NFBColorFromHex(0xff7a00);
    case 6: return NFBColorFromHex(0x00ba7c);
    default: return NFBColorFromHex(0x1d9bf0);
  }
}

NSString *NFBAccentColorNameForID(NSInteger colorID) {
  switch (colorID) {
    case 1: return @"Blue";
    case 2: return @"Yellow";
    case 3: return @"Pink";
    case 4: return @"Purple";
    case 5: return @"Orange";
    case 6: return @"Green";
    default: return @"Blue";
  }
}

void NFBSetAccentColorID(NSInteger colorID) {
  if (colorID < 1 || colorID > 6) colorID = 1;
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setInteger:colorID forKey:NFBColorThemeSelectedKey];
  [defaults setInteger:colorID forKey:NFBColorThemeLastSelectedKey];
  [defaults setInteger:colorID forKey:NFBTwitterPrimaryColorOptionKey];
  [defaults synchronize];
  NFBApplyThemeToVisibleWindows();
  [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
}

CGFloat NFBIPAMetricValue(NFBIPAMetric metric) {
  switch (metric) {
    case NFBIPAMetricTimelineHorizontalInset: return 16.0;
    case NFBIPAMetricTimelineAvatarSize: return 48.0;
    case NFBIPAMetricTimelineAvatarTextGap: return 12.0;
    case NFBIPAMetricTimelineTopInset: return 12.0;
    case NFBIPAMetricTimelineContentTopInset: return 10.0;
    case NFBIPAMetricTimelineBottomInset: return 7.0;
    case NFBIPAMetricTimelineReasonAvatarTopInset: return 31.0;
    case NFBIPAMetricTimelineMetaFontSize: return 15.0;
    case NFBIPAMetricTimelineBodyFontSize: return 15.0;
    case NFBIPAMetricTimelineActionHeight: return 34.0;
    case NFBIPAMetricTimelineActionButtonMinWidth: return 34.0;
    case NFBIPAMetricTimelineActionIconSize: return 18.0;
    case NFBIPAMetricTimelineActionLabelGap: return 5.0;
    case NFBIPAMetricVerifiedBadgeSize: return 15.0;
    case NFBIPAMetricThreadRailWidth: return 2.0;
    case NFBIPAMetricThreadRailAvatarGap: return 4.0;
    case NFBIPAMetricEmbeddedCardCornerRadius: return 12.0;
    case NFBIPAMetricEmbeddedCardInset: return 10.0;
    case NFBIPAMetricEmbeddedCardStackSpacing: return 3.0;
    case NFBIPAMetricEmbeddedCardAvatarSize: return 20.0;
    case NFBIPAMetricEmbeddedCardNameFontSize: return 15.0;
    case NFBIPAMetricEmbeddedCardBodyFontSize: return 15.0;
    case NFBIPAMetricComposerBodyFontSize: return 17.0;
    case NFBIPAMetricMessageBodyFontSize: return 14.0;
    // Twitter 9.67 tweetDetailFont/readerModeMediumFont use headline2 (body + 2).
    case NFBIPAMetricDetailBodyFontSize: return 17.0;
    case NFBIPAMetricDetailFooterFontSize: return 14.0;
    case NFBIPAMetricDetailActionButtonWidth: return 44.0;
    case NFBIPAMetricDetailActionIconSize: return 24.0;
    case NFBIPAMetricMediaViewerChromeIconSize: return 24.0;
    case NFBIPAMetricMediaViewerActionIconSize: return 24.0;
  }
  return 0.0;
}

static UIColor *NFBResolvedIPAColor(NFBIPAColorRole role) {
  NSString *mode = NFBIPAResolvedDisplayMode();
  BOOL light = [mode isEqualToString:NFBDisplayModeLight];
  BOOL dim = [mode isEqualToString:NFBDisplayModeDim];
  switch (role) {
    case NFBIPAColorRolePrimary:
      return NFBNeoFreeBirdAccentColor();
    case NFBIPAColorRoleText:
      if (light) return NFBColorFromHex(0x0f1419);
      if (dim) return NFBColorFromHex(0xffffff);
      return NFBColorFromHex(0xd9d9d9);
    case NFBIPAColorRoleTextDetails:
      if (light) return NFBColorFromHex(0x536471);
      if (dim) return NFBColorFromHex(0x8b98a5);
      return NFBColorFromHex(0x71767b);
    case NFBIPAColorRoleTextPlaceholder:
      if (light) return NFBColorFromHex(0x536471);
      if (dim) return NFBColorFromHex(0x8b98a5);
      return NFBColorFromHex(0x71767b);
    case NFBIPAColorRoleBackground:
      if (light) return UIColor.whiteColor;
      if (dim) return NFBColorFromHex(0x15202b);
      return UIColor.blackColor;
    case NFBIPAColorRoleFaintBackground:
      if (light) return NFBColorFromHex(0xf7f9f9);
      if (dim) return NFBColorFromHex(0x1e2732);
      return NFBColorFromHex(0x16181c);
    case NFBIPAColorRoleElevatedBackground:
      if (light) return UIColor.whiteColor;
      if (dim) return NFBColorFromHex(0x1c2c3c);
      return NFBColorFromHex(0x1b2023);
    case NFBIPAColorRoleDivider:
      if (light) return NFBColorFromHex(0xcfd9de);
      if (dim) return NFBColorFromHex(0x38444d);
      return NFBColorFromHex(0x333639);
    case NFBIPAColorRoleGroupedDivider:
      if (light) return NFBColorFromHex(0xb9cad3);
      if (dim) return NFBColorFromHex(0x5c6e7e);
      return NFBColorFromHex(0x3e4144);
    case NFBIPAColorRoleDarkBackground:
      return UIColor.blackColor;
    case NFBIPAColorRoleHighlightOverlay:
      return [NFBResolvedIPAColor(NFBIPAColorRoleText) colorWithAlphaComponent:light ? 0.08 : 0.12];
    case NFBIPAColorRoleNavigationBarShadow:
      return [NFBResolvedIPAColor(NFBIPAColorRoleDivider) colorWithAlphaComponent:0.72];
    case NFBIPAColorRoleTabBarBackground:
      return dim ? NFBColorFromHex(0x1a242c) : NFBResolvedIPAColor(NFBIPAColorRoleBackground);
    case NFBIPAColorRoleTabBarDivider:
      return [NFBResolvedIPAColor(NFBIPAColorRoleDivider) colorWithAlphaComponent:0.72];
    case NFBIPAColorRoleDashDrawerBackground:
      return NFBResolvedIPAColor(NFBIPAColorRoleBackground);
    case NFBIPAColorRoleDashDrawerText:
      return NFBResolvedIPAColor(NFBIPAColorRoleText);
    case NFBIPAColorRoleDashDrawerTextDetails:
      return NFBResolvedIPAColor(NFBIPAColorRoleTextDetails);
    case NFBIPAColorRoleDashDrawerDivider:
      return NFBResolvedIPAColor(NFBIPAColorRoleDivider);
    case NFBIPAColorRoleDashDrawerScrim:
      return [(light ? NFBColorFromHex(0xcfd9de) : dim ? UIColor.blackColor : NFBColorFromHex(0x202327)) colorWithAlphaComponent:NFBIPADashDrawerScrimAlpha()];
    case NFBIPAColorRoleModalSheetScrim:
      return [(light || dim ? UIColor.blackColor : NFBColorFromHex(0x202327)) colorWithAlphaComponent:NFBIPAModalSheetBackdropAlpha()];
    case NFBIPAColorRoleSearchField:
      return light ? NFBColorFromHex(0xeff3f4) : NFBResolvedIPAColor(NFBIPAColorRoleFaintBackground);
    case NFBIPAColorRoleModalSheetBackground:
      return NFBResolvedIPAColor(NFBIPAColorRoleBackground);
    case NFBIPAColorRoleModalSheetGrabber:
      return NFBColorFromHex(light ? 0xeff3f4 : dim ? 0x243447 : 0x202327);
    case NFBIPAColorRoleModalSheetRowHighlight:
      return [NFBResolvedIPAColor(NFBIPAColorRoleText) colorWithAlphaComponent:light ? 0.08 : 0.12];
  }
  return UIColor.clearColor;
}

// Keep the semantic role so an existing view can also refresh between Dim and
// Lights out, which share UIKit's dark trait. Fixed on-media colors stay fixed.
// Each styled control keeps its latest appearance recipe. In particular,
// CALayer CGColors are snapshots and cannot follow dynamic UIColor changes.
@interface NFBThemeObservation : NSObject
@property (nonatomic, weak) id owner;
@property (nonatomic, copy) void (^update)(id owner);
@end
@implementation NFBThemeObservation
- (void)themeChanged:(NSNotification *)notification {
  id owner = self.owner;
  void (^update)(id) = self.update;
  if (owner && update) update(owner);
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

static char NFBThemeObservationKey;
static void NFBObserveAppearance(id owner, void (^update)(id owner)) {
  if (!owner) return;
  NFBThemeObservation *observation = objc_getAssociatedObject(owner, &NFBThemeObservationKey);
  if (!observation) {
    observation = [NFBThemeObservation new];
    observation.owner = owner;
    objc_setAssociatedObject(owner, &NFBThemeObservationKey, observation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [[NSNotificationCenter defaultCenter] addObserver:observation selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  }
  observation.update = update;
}

static char NFBThemeColorRoleKey;
UIColor *NFBIPAColor(NFBIPAColorRole role) {
  UIColor *color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
    return NFBResolvedIPAColor(role);
  }];
  objc_setAssociatedObject(color, &NFBThemeColorRoleKey, @(role), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return color;
}

UIColor *NFBColorBackground(void) { return NFBIPAColor(NFBIPAColorRoleBackground); }
UIColor *NFBColorElevatedBackground(void) { return NFBIPAColor(NFBIPAColorRoleElevatedBackground); }
UIColor *NFBColorText(void) { return NFBIPAColor(NFBIPAColorRoleText); }
UIColor *NFBColorSecondaryText(void) { return NFBIPAColor(NFBIPAColorRoleTextDetails); }
UIColor *NFBColorTertiaryText(void) { return NFBIPAColor(NFBIPAColorRoleTextPlaceholder); }
UIColor *NFBColorBorder(void) { return NFBIPAColor(NFBIPAColorRoleDivider); }
UIColor *NFBColorAccent(void) { return NFBIPAColor(NFBIPAColorRolePrimary); }
UIColor *NFBColorBlue(void) { return NFBColorFromHex(0x1d9bf0); }

UIBlurEffect *NFBIPATabBarBackgroundEffect(void) {
  return [UIBlurEffect effectWithStyle:NFBTabBarBlurEffectStyle()];
}

UIColor *NFBIPADashDrawerBackgroundColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDashDrawerBackground);
}

UIColor *NFBIPADashDrawerPrimaryTextColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDashDrawerText);
}

UIColor *NFBIPADashDrawerSecondaryTextColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDashDrawerTextDetails);
}

UIColor *NFBIPADashDrawerSeparatorColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDashDrawerDivider);
}

CGFloat NFBIPADashDrawerScrimAlpha(void) {
  return [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? 0.60 : 0.75;
}

UIColor *NFBIPADashDrawerScrimColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDashDrawerScrim);
}

CGFloat NFBIPAModalSheetBackdropAlpha(void) {
  NSString *mode = NFBCurrentDisplayMode();
  return [mode isEqualToString:NFBDisplayModeLight] ? 0.475 : [mode isEqualToString:NFBDisplayModeDim] ? 0.65 : 0.75;
}

UIColor *NFBIPAModalSheetScrimColor(void) {
  return NFBIPAColor(NFBIPAColorRoleModalSheetScrim);
}

UIColor *NFBIPAModalSheetBackgroundColor(void) {
  return NFBIPAColor(NFBIPAColorRoleModalSheetBackground);
}

UIColor *NFBIPAModalSheetGrabberColor(void) {
  return NFBIPAColor(NFBIPAColorRoleModalSheetGrabber);
}

UIColor *NFBIPAModalSheetRowHighlightColor(void) {
  return NFBIPAColor(NFBIPAColorRoleModalSheetRowHighlight);
}

CGFloat NFBIPAModalSheetCornerRadius(void) {
  return 35.0;
}

CGFloat NFBIPAModalSheetRowHeight(void) {
  return 60.0;
}

void NFBIPAApplyModalSheetAppearance(UIView *sheetView) {
  NFBObserveAppearance(sheetView, ^(id owner) { NFBIPAApplyModalSheetAppearance(owner); });
  sheetView.backgroundColor = NFBIPAModalSheetBackgroundColor();
  sheetView.layer.cornerRadius = NFBIPAModalSheetCornerRadius();
  if (@available(iOS 13.0, *)) {
    sheetView.layer.cornerCurve = kCACornerCurveContinuous;
  }
  if (@available(iOS 11.0, *)) {
    sheetView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
  }
  sheetView.layer.masksToBounds = YES;
  sheetView.clipsToBounds = YES;
}

void NFBIPAApplyModalSheetGrabberAppearance(UIView *grabber) {
  NFBObserveAppearance(grabber, ^(id owner) { NFBIPAApplyModalSheetGrabberAppearance(owner); });
  grabber.backgroundColor = NFBIPAModalSheetGrabberColor();
  grabber.layer.cornerRadius = 2.5;
}

UIColor *NFBIPATableCellSelectedBackgroundColor(void) {
  return NFBIPAColor(NFBIPAColorRoleHighlightOverlay);
}

UIColor *NFBIPATableSeparatorColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDivider);
}

CGFloat NFBIPATableSeparatorHeight(void) {
  return 1.0 / UIScreen.mainScreen.scale;
}

UIColor *NFBIPAThreadRailColor(void) {
  return NFBIPAColor(NFBIPAColorRoleGroupedDivider);
}

UIColor *NFBIPAEmbeddedCardBorderColor(void) {
  return NFBIPAColor(NFBIPAColorRoleDivider);
}

void NFBIPAApplyEmbeddedCardFrameAppearance(UIView *view) {
  NFBObserveAppearance(view, ^(id owner) { NFBIPAApplyEmbeddedCardFrameAppearance(owner); });
  if (!view) return;
  view.backgroundColor = NFBColorBackground();
  view.clipsToBounds = YES;
  view.layer.cornerRadius = NFBIPAMetricValue(NFBIPAMetricEmbeddedCardCornerRadius);
  view.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  view.layer.borderColor = NFBIPAEmbeddedCardBorderColor().CGColor;
}

void NFBIPAApplyEmbeddedAttachmentFrameAppearance(UIView *view) {
  NFBObserveAppearance(view, ^(id owner) { NFBIPAApplyEmbeddedAttachmentFrameAppearance(owner); });
  view.backgroundColor = NFBColorBackground();
  view.clipsToBounds = YES;
  view.layer.cornerRadius = 0.0;
  view.layer.borderWidth = 0.0;
  view.layer.borderColor = UIColor.clearColor.CGColor;
}

void NFBIPAApplyTableViewAppearance(UITableView *tableView) {
  NFBObserveAppearance(tableView, ^(id owner) { NFBIPAApplyTableViewAppearance(owner); });
  tableView.backgroundColor = NFBColorBackground();
  tableView.separatorColor = NFBIPATableSeparatorColor();
  tableView.indicatorStyle = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? UIScrollViewIndicatorStyleBlack : UIScrollViewIndicatorStyleWhite;
  tableView.tintColor = NFBColorAccent();
  SEL headerPaddingSelector = NSSelectorFromString(@"setSectionHeaderTopPadding:");
  if ([tableView respondsToSelector:headerPaddingSelector]) {
    [tableView setValue:@0.0 forKey:@"sectionHeaderTopPadding"];
  }
}

void NFBIPAApplyTableCellAppearance(UITableViewCell *cell, UITableViewCellSelectionStyle selectionStyle) {
  NFBObserveAppearance(cell, ^(id owner) { NFBIPAApplyTableCellAppearance(owner, selectionStyle); });
  cell.backgroundColor = NFBColorBackground();
  cell.contentView.backgroundColor = NFBColorBackground();
  cell.selectionStyle = selectionStyle;
  cell.tintColor = NFBColorAccent();
  if (selectionStyle == UITableViewCellSelectionStyleNone) {
    cell.selectedBackgroundView = nil;
    cell.multipleSelectionBackgroundView = nil;
    return;
  }
  UIView *selectedView = cell.selectedBackgroundView ?: [[UIView alloc] initWithFrame:CGRectZero];
  selectedView.backgroundColor = NFBIPATableCellSelectedBackgroundColor();
  cell.selectedBackgroundView = selectedView;
  UIView *multipleSelectedView = cell.multipleSelectionBackgroundView ?: [[UIView alloc] initWithFrame:CGRectZero];
  multipleSelectedView.backgroundColor = NFBIPATableCellSelectedBackgroundColor();
  cell.multipleSelectionBackgroundView = multipleSelectedView;
}

void NFBIPAApplyTableSeparatorAppearance(UIView *separatorView) {
  separatorView.backgroundColor = NFBIPATableSeparatorColor();
}

UIColor *NFBIPASearchFieldBackgroundColor(void) {
  return NFBIPAColor(NFBIPAColorRoleSearchField);
}

void NFBIPAApplySearchContainerAppearance(UIView *container) {
  NFBObserveAppearance(container, ^(id owner) { NFBIPAApplySearchContainerAppearance(owner); });
  container.backgroundColor = NFBIPASearchFieldBackgroundColor();
  container.layer.cornerRadius = 18.0;
  container.layer.masksToBounds = YES;
  container.clipsToBounds = YES;
  if (@available(iOS 13.0, *)) {
    container.layer.cornerCurve = kCACornerCurveContinuous;
  }
}

void NFBIPAApplySearchTextFieldAppearance(UITextField *textField, NSString *placeholder) {
  NFBObserveAppearance(textField, ^(id owner) { NFBIPAApplySearchTextFieldAppearance(owner, placeholder); });
  textField.borderStyle = UITextBorderStyleNone;
  textField.textColor = NFBColorText();
  textField.tintColor = NFBColorAccent();
  textField.font = NFBFont(17.0, NFBFontWeightRegular);
  textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder ?: @""
                                                                    attributes:@{
    NSForegroundColorAttributeName: NFBColorSecondaryText(),
    NSFontAttributeName: NFBFont(17.0, NFBFontWeightRegular)
  }];
}

void NFBIPAApplyLegacyFormTextFieldAppearance(UITextField *textField, NSString *placeholder, BOOL focused) {
  NFBObserveAppearance(textField, ^(id owner) { NFBIPAApplyLegacyFormTextFieldAppearance(owner, placeholder, [owner isFirstResponder]); });
  textField.borderStyle = UITextBorderStyleNone;
  textField.backgroundColor = NFBColorBackground();
  textField.textColor = NFBColorText();
  textField.tintColor = NFBColorAccent();
  textField.font = NFBFont(18.0, NFBFontWeightRegular);
  textField.layer.cornerRadius = 4.0;
  textField.layer.borderColor = (focused ? NFBColorAccent() : NFBColorBorder()).CGColor;
  textField.layer.borderWidth = focused ? 2.0 : 1.0;
  textField.layer.masksToBounds = YES;
  textField.clipsToBounds = YES;
  textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder ?: @""
                                                                    attributes:@{
    NSForegroundColorAttributeName: NFBColorSecondaryText(),
    NSFontAttributeName: NFBFont(18.0, NFBFontWeightRegular)
  }];
}

@implementation NFBPillButton
- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
  CGFloat diameter = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
  self.layer.cornerRadius = floor(MAX(0.0, diameter) * 0.5 * scale) / scale;
  self.layer.cornerCurve = kCACornerCurveCircular;
}
@end

static UIEdgeInsets NFBIPAButtonContentEdgeInsets(NFBIPAButtonSize size) {
  switch (size) {
    case NFBIPAButtonSizeCompact: return UIEdgeInsetsMake(4.0, 12.0, 4.0, 12.0);
    case NFBIPAButtonSizeSmall: return UIEdgeInsetsMake(8.0, 16.0, 8.0, 16.0);
    case NFBIPAButtonSizeMedium: return UIEdgeInsetsMake(8.0, 16.0, 8.0, 16.0);
    case NFBIPAButtonSizeLarge: return UIEdgeInsetsMake(12.0, 24.0, 12.0, 24.0);
  }
  return UIEdgeInsetsMake(8.0, 16.0, 8.0, 16.0);
}

static UIFont *NFBIPAButtonFont(NFBIPAButtonSize size) {
  switch (size) {
    case NFBIPAButtonSizeCompact: return NFBFont(14.0, NFBFontWeightBold);
    case NFBIPAButtonSizeSmall: return NFBFont(14.0, NFBFontWeightBold);
    case NFBIPAButtonSizeMedium: return NFBFont(15.0, NFBFontWeightBold);
    case NFBIPAButtonSizeLarge: return NFBFont(15.0, NFBFontWeightBold);
  }
  return NFBFont(15.0, NFBFontWeightBold);
}

static void NFBIPASetButtonColors(UIButton *button, UIColor *backgroundColor, UIColor *titleColor, UIColor *borderColor, CGFloat borderWidth) {
  button.backgroundColor = backgroundColor;
  [button setTitleColor:titleColor forState:UIControlStateNormal];
  [button setTitleColor:[titleColor colorWithAlphaComponent:0.48] forState:UIControlStateDisabled];
  button.tintColor = titleColor;
  button.layer.borderColor = borderColor.CGColor;
  button.layer.borderWidth = borderWidth;
}

void NFBIPAApplyButtonAppearance(UIButton *button, NFBIPAButtonStyle style, NFBIPAButtonSize size) {
  NFBObserveAppearance(button, ^(id owner) { NFBIPAApplyButtonAppearance(owner, style, size); });
  button.titleLabel.font = NFBIPAButtonFont(size);
  button.contentEdgeInsets = NFBIPAButtonContentEdgeInsets(size);
  [button setNeedsLayout];
  button.layer.masksToBounds = YES;
  button.clipsToBounds = YES;
  if (@available(iOS 13.0, *)) {
    button.layer.cornerCurve = kCACornerCurveContinuous;
  }

  switch (style) {
    case NFBIPAButtonStylePrimary:
      NFBIPASetButtonColors(button, NFBColorAccent(), UIColor.whiteColor, UIColor.clearColor, 0.0);
      break;
    case NFBIPAButtonStyleSecondary:
      NFBIPASetButtonColors(button, NFBColorText(), NFBColorBackground(), UIColor.clearColor, 0.0);
      break;
    case NFBIPAButtonStyleOutline:
      NFBIPASetButtonColors(button, UIColor.clearColor, NFBColorAccent(), [NFBColorAccent() colorWithAlphaComponent:0.75], 1.0);
      break;
    case NFBIPAButtonStyleNeutralOutline:
      NFBIPASetButtonColors(button, UIColor.clearColor, NFBColorText(), NFBColorBorder(), 1.0);
      break;
    case NFBIPAButtonStyleText:
      NFBIPASetButtonColors(button, UIColor.clearColor, NFBColorAccent(), UIColor.clearColor, 0.0);
      break;
    case NFBIPAButtonStyleDestructive:
      NFBIPASetButtonColors(button, UIColor.clearColor, UIColor.systemRedColor, UIColor.systemRedColor, 1.0);
      break;
    case NFBIPAButtonStyleOnDarkPrimary:
      NFBIPASetButtonColors(button, UIColor.whiteColor, UIColor.blackColor, UIColor.clearColor, 0.0);
      break;
    case NFBIPAButtonStyleOnDarkOutline:
      NFBIPASetButtonColors(button, [UIColor.whiteColor colorWithAlphaComponent:0.13], UIColor.whiteColor, [UIColor.whiteColor colorWithAlphaComponent:0.72], 1.0);
      break;
  }
}

void NFBIPAApplyFollowButtonAppearance(UIButton *button, BOOL following, BOOL destructive, BOOL overDarkBackground) {
  NFBObserveAppearance(button, ^(id owner) { NFBIPAApplyFollowButtonAppearance(owner, following, destructive, overDarkBackground); });
  button.titleLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
  button.contentEdgeInsets = UIEdgeInsetsMake(5.0, 13.0, 5.0, 13.0);
  [button setNeedsLayout];
  button.layer.masksToBounds = YES;
  button.clipsToBounds = YES;
  if (@available(iOS 13.0, *)) {
    button.layer.cornerCurve = kCACornerCurveContinuous;
  }

  if (overDarkBackground) {
    if (following || destructive) {
      UIColor *titleColor = destructive ? UIColor.systemRedColor : UIColor.whiteColor;
      UIColor *borderColor = destructive ? UIColor.systemRedColor : [UIColor.whiteColor colorWithAlphaComponent:0.72];
      NFBIPASetButtonColors(button, [UIColor.whiteColor colorWithAlphaComponent:0.13], titleColor, borderColor, 1.0);
    } else {
      NFBIPASetButtonColors(button, UIColor.whiteColor, UIColor.blackColor, UIColor.clearColor, 0.0);
    }
  } else {
    if (following || destructive) {
      UIColor *titleColor = destructive ? UIColor.systemRedColor : NFBColorText();
      UIColor *borderColor = destructive ? UIColor.systemRedColor : NFBColorSecondaryText();
      NFBIPASetButtonColors(button, UIColor.clearColor, titleColor, borderColor, 1.0);
    } else {
      NFBIPASetButtonColors(button, NFBColorText(), NFBColorBackground(), UIColor.clearColor, 0.0);
    }
  }
}

UIColor *NFBIPAMessageOutgoingBubbleColor(void) {
  return NFBColorAccent();
}

UIColor *NFBIPAMessageIncomingBubbleColor(void) {
  return NFBIPAColor(NFBIPAColorRoleSearchField);
}

UIColor *NFBIPAMessageInputBackgroundColor(void) {
  return NFBIPASearchFieldBackgroundColor();
}

void NFBIPAApplyMessageInputContainerAppearance(UIView *container) {
  NFBObserveAppearance(container, ^(id owner) { NFBIPAApplyMessageInputContainerAppearance(owner); });
  container.backgroundColor = NFBIPAMessageInputBackgroundColor();
  container.layer.cornerRadius = 22.0;
  container.layer.masksToBounds = YES;
  container.clipsToBounds = YES;
  if (@available(iOS 13.0, *)) {
    container.layer.cornerCurve = kCACornerCurveContinuous;
  }
}

void NFBIPAApplyMessageBubbleAppearance(UIView *bubbleView, BOOL outgoing) {
  NFBObserveAppearance(bubbleView, ^(id owner) { NFBIPAApplyMessageBubbleAppearance(owner, outgoing); });
  bubbleView.backgroundColor = outgoing ? NFBIPAMessageOutgoingBubbleColor() : NFBIPAMessageIncomingBubbleColor();
  bubbleView.layer.cornerRadius = 22.0;
  bubbleView.layer.masksToBounds = YES;
  bubbleView.clipsToBounds = YES;
  if (@available(iOS 13.0, *)) {
    bubbleView.layer.cornerCurve = kCACornerCurveContinuous;
  }
}

void NFBIPAApplyMessageReactionPillAppearance(UILabel *reactionLabel) {
  NFBObserveAppearance(reactionLabel, ^(id owner) { NFBIPAApplyMessageReactionPillAppearance(owner); });
  reactionLabel.textColor = NFBColorText();
  reactionLabel.backgroundColor = NFBColorBackground();
  reactionLabel.layer.cornerRadius = 12.0;
  reactionLabel.layer.borderColor = NFBIPAColor(NFBIPAColorRoleDivider).CGColor;
  reactionLabel.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  reactionLabel.layer.masksToBounds = YES;
  reactionLabel.clipsToBounds = YES;
}

void NFBIPAApplyMessageReactionTrayAppearance(UIView *trayView) {
  NFBObserveAppearance(trayView, ^(id owner) { NFBIPAApplyMessageReactionTrayAppearance(owner); });
  trayView.backgroundColor = NFBColorBackground();
  trayView.layer.cornerRadius = 28.0;
  trayView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  trayView.layer.borderColor = NFBIPAColor(NFBIPAColorRoleGroupedDivider).CGColor;
  trayView.layer.shadowColor = UIColor.blackColor.CGColor;
  trayView.layer.shadowOpacity = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? 0.16 : 0.36;
  trayView.layer.shadowOffset = CGSizeMake(0.0, 8.0);
  trayView.layer.shadowRadius = 18.0;
  trayView.layer.masksToBounds = NO;
  trayView.clipsToBounds = NO;
  if (@available(iOS 13.0, *)) {
    trayView.layer.cornerCurve = kCACornerCurveContinuous;
  }
}

void NFBIPAApplyMessageSendButtonAppearance(UIButton *button, BOOL active) {
  NFBObserveAppearance(button, ^(id owner) { NFBIPAApplyMessageSendButtonAppearance(owner, active); });
  button.tintColor = active ? UIColor.whiteColor : NFBColorSecondaryText();
  button.backgroundColor = active ? NFBColorAccent() : UIColor.clearColor;
  button.layer.cornerRadius = 20.0;
  button.layer.masksToBounds = YES;
  button.clipsToBounds = YES;
  button.alpha = active ? 1.0 : 0.58;
  if (@available(iOS 13.0, *)) {
    button.layer.cornerCurve = kCACornerCurveContinuous;
  }
}

BOOL NFBIPAProfileFollowsViewer(NSDictionary *profile) {
  if (![profile isKindOfClass:NSDictionary.class]) return NO;
  NSDictionary *viewer = [profile[@"viewer"] isKindOfClass:NSDictionary.class] ? profile[@"viewer"] : @{};
  return [viewer[@"followedBy"] isKindOfClass:NSString.class] && [viewer[@"followedBy"] length] > 0;
}

void NFBIPAApplyFollowsYouBadgeAppearance(UILabel *label) {
  NFBObserveAppearance(label, ^(id owner) { NFBIPAApplyFollowsYouBadgeAppearance(owner); });
  label.text = @"Follows you";
  label.font = NFBFont(12.0, NFBFontWeightBold);
  label.textColor = NFBColorSecondaryText();
  label.textAlignment = NSTextAlignmentCenter;
  label.numberOfLines = 1;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  CGFloat alpha = [NFBCurrentDisplayMode() isEqualToString:NFBDisplayModeLight] ? 0.12 : 0.18;
  label.backgroundColor = [NFBColorSecondaryText() colorWithAlphaComponent:alpha];
  label.layer.cornerRadius = 4.0;
  label.layer.masksToBounds = YES;
  label.clipsToBounds = YES;
}

UIColor *NFBIPAOnMediaBarBackgroundColor(void) {
  return UIColor.blackColor;
}

UIColor *NFBIPAOnMediaSeparatorColor(void) {
  return [UIColor.whiteColor colorWithAlphaComponent:0.18];
}

UIColor *NFBIPAOnMediaPrimaryTextColor(void) {
  return UIColor.whiteColor;
}

UIColor *NFBIPAOnMediaSecondaryTextColor(void) {
  return [UIColor.whiteColor colorWithAlphaComponent:0.82];
}

UIColor *NFBIPAOnMediaMutedTextColor(void) {
  return [UIColor.whiteColor colorWithAlphaComponent:0.58];
}

void NFBIPAApplyOnMediaBarAppearance(UIView *barView) {
  barView.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
}

void NFBIPAApplyOnMediaSeparatorAppearance(UIView *separatorView) {
  separatorView.backgroundColor = NFBIPAOnMediaSeparatorColor();
}

void NFBIPAApplyOnMediaIconButtonAppearance(UIButton *button, BOOL selected, CGFloat cornerRadius) {
  UIColor *tintColor = selected ? NFBColorAccent() : NFBIPAOnMediaSecondaryTextColor();
  button.selected = selected;
  button.tintColor = tintColor;
  [button setTitleColor:tintColor forState:UIControlStateNormal];
  [button setTitleColor:NFBColorAccent() forState:UIControlStateSelected];
  button.backgroundColor = selected ? [UIColor.whiteColor colorWithAlphaComponent:0.16] : UIColor.clearColor;
  button.layer.cornerRadius = cornerRadius;
  button.layer.masksToBounds = cornerRadius > 0.0;
  button.clipsToBounds = cornerRadius > 0.0;
}

void NFBIPAApplyOnMediaFloatingButtonAppearance(UIButton *button, CGFloat cornerRadius) {
  button.tintColor = NFBIPAOnMediaPrimaryTextColor();
  [button setTitleColor:NFBIPAOnMediaPrimaryTextColor() forState:UIControlStateNormal];
  button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.46];
  button.layer.cornerRadius = cornerRadius;
  button.layer.masksToBounds = YES;
  button.clipsToBounds = YES;
}

void NFBIPAApplyOnMediaLabelPillAppearance(UILabel *label, CGFloat cornerRadius) {
  label.textColor = NFBIPAOnMediaPrimaryTextColor();
  label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.78];
  label.layer.cornerRadius = cornerRadius;
  label.layer.masksToBounds = YES;
  label.clipsToBounds = YES;
}

static UIColor *NFBTwitterCloneSidebarBackgroundColor(void) {
  return NFBIPAColor(NFBIPAColorRoleFaintBackground);
}

static UIColor *NFBTwitterCloneTombstoneBorderColor(void) {
  return NFBIPAColor(NFBIPAColorRoleGroupedDivider);
}

UIFont *NFBFont(CGFloat size, NFBFontWeight weight) {
  NFBRegisterBundledFonts();
  CGFloat scaledSize = MAX(10.0, round(size * NFBCurrentFontScale() * UIScreen.mainScreen.scale) / UIScreen.mainScreen.scale);
  NSString *name = @"Chirp-Regular";
  UIFontWeight fallback = UIFontWeightRegular;
  switch (weight) {
    case NFBFontWeightMedium:
      name = @"Chirp-Medium";
      fallback = UIFontWeightSemibold;
      break;
    case NFBFontWeightBold:
      name = @"Chirp-Bold";
      fallback = UIFontWeightBold;
      break;
    case NFBFontWeightHeavy:
      name = @"Chirp-Heavy";
      fallback = UIFontWeightHeavy;
      break;
    case NFBFontWeightRegular:
    default:
      break;
  }
  UIFont *font = [UIFont fontWithName:name size:scaledSize];
  if (!font) return [UIFont systemFontOfSize:scaledSize weight:fallback];
  // Twitter 9.67 ships separate Cyrillic faces. Keep their weight aligned with
  // the Latin face instead of letting mixed-language posts fall back to SF.
  NSString *cyrillicName = [name stringByReplacingOccurrencesOfString:@"Chirp-" withString:@"ChirpCY-"];
  UIFont *cyrillicFont = [UIFont fontWithName:cyrillicName size:scaledSize];
  if (!cyrillicFont) return font;
  UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
    UIFontDescriptorCascadeListAttribute: @[cyrillicFont.fontDescriptor]
  }];
  return [UIFont fontWithDescriptor:descriptor size:scaledSize];
}

static NSString *NFBShortCountWithSuffix(double value, NSString *suffix, BOOL allowDecimal) {
  NSString *number = allowDecimal ? [NSString stringWithFormat:@"%.1f", value] : [NSString stringWithFormat:@"%.0f", value];
  if ([number hasSuffix:@".0"]) number = [number substringToIndex:number.length - 2];
  return [number stringByAppendingString:suffix];
}

NSString *NFBShortCountString(NSInteger count) {
  if (count < 0) count = 0;
  if (count < 1000) return [NSString stringWithFormat:@"%ld", (long)count];
  if (count < 999500) {
    double thousands = count / 1000.0;
    return NFBShortCountWithSuffix(thousands, @"K", count < 10000);
  }
  double millions = count / 1000000.0;
  return NFBShortCountWithSuffix(millions, @"M", count < 10000000);
}

static NSURL *NFBInternalTextLinkURL(NSString *host, NSString *key, NSString *value) {
  if (host.length == 0 || value.length == 0) return nil;
  NSURLComponents *components = [[NSURLComponents alloc] init];
  components.scheme = @"nottwitter";
  components.host = host;
  components.queryItems = @[[NSURLQueryItem queryItemWithName:key ?: @"value" value:value]];
  return components.URL;
}

static NSString *NFBTrimmedTweetToken(NSString *token) {
  return [token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

static NSURL *NFBExternalURLForString(NSString *urlString) {
  NSString *trimmed = NFBTrimmedTweetToken(urlString);
  if (trimmed.length == 0) return nil;
  NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
  if (components.scheme.length == 0 && [trimmed.lowercaseString hasPrefix:@"www."]) {
    trimmed = [@"https://" stringByAppendingString:trimmed];
  }
  return [NSURL URLWithString:trimmed];
}

static NSString *NFBShortDisplayURLString(NSString *urlString, NSString *fallback) {
  NSString *candidate = NFBTrimmedTweetToken(urlString.length > 0 ? urlString : fallback);
  NSURLComponents *components = [NSURLComponents componentsWithString:candidate];
  NSString *display = candidate;
  if (components.host.length > 0) {
    NSString *host = components.host ?: @"";
    if ([host.lowercaseString hasPrefix:@"www."]) host = [host substringFromIndex:4];
    NSString *path = components.percentEncodedPath.length > 0 ? components.percentEncodedPath : @"";
    NSString *query = components.percentEncodedQuery.length > 0 ? [@"?" stringByAppendingString:components.percentEncodedQuery] : @"";
    display = [[host stringByAppendingString:path] stringByAppendingString:query];
  } else {
    NSArray<NSString *> *schemes = @[@"https://", @"http://"];
    for (NSString *scheme in schemes) {
      if ([display.lowercaseString hasPrefix:scheme]) {
        display = [display substringFromIndex:scheme.length];
        break;
      }
    }
    if ([display.lowercaseString hasPrefix:@"www."]) display = [display substringFromIndex:4];
  }
  while ([display hasSuffix:@"/"] && display.length > 1) display = [display substringToIndex:display.length - 1];
  if (display.length > 34) display = [[display substringToIndex:33] stringByAppendingString:@"…"];
  return display.length > 0 ? display : candidate;
}

static NSURL *NFBURLForFacetFeature(NSDictionary *feature, NSString *token, NSString **displayOverride) {
  if (![feature isKindOfClass:NSDictionary.class]) return nil;
  NSString *type = [feature[@"$type"] isKindOfClass:NSString.class] ? feature[@"$type"] : @"";
  if (type.length == 0) type = [feature[@"type"] isKindOfClass:NSString.class] ? feature[@"type"] : @"";
  if ([type containsString:@"#link"]) {
    NSString *uri = [feature[@"uri"] isKindOfClass:NSString.class] ? feature[@"uri"] : @"";
    NSURL *url = NFBExternalURLForString(uri);
    // Preserve labels supplied by another client (for example, "read this").
    if (displayOverride && ([uri caseInsensitiveCompare:token] == NSOrderedSame ||
        [uri caseInsensitiveCompare:[@"https://" stringByAppendingString:token]] == NSOrderedSame))
      *displayOverride = NFBShortDisplayURLString(uri, token);
    return url;
  }
  if ([type containsString:@"#mention"]) {
    NSString *actor = [feature[@"did"] isKindOfClass:NSString.class] ? feature[@"did"] : @"";
    if (actor.length == 0) actor = [feature[@"handle"] isKindOfClass:NSString.class] ? feature[@"handle"] : @"";
    return NFBInternalTextLinkURL(@"profile", @"actor", actor);
  }
  if ([type containsString:@"#tag"]) {
    NSString *tag = [feature[@"tag"] isKindOfClass:NSString.class] ? feature[@"tag"] : @"";
    if (tag.length == 0 && [token hasPrefix:@"#"]) tag = [token substringFromIndex:1];
    NSString *query = [tag hasPrefix:@"#"] ? tag : [@"#" stringByAppendingString:tag ?: @""];
    return NFBInternalTextLinkURL(@"search", @"query", query);
  }
  return nil;
}

static NSDictionary *NFBDisplayTextAndLinksForRecord(NSDictionary *record, BOOL shortenURLs) {
  NSString *text = [record[@"text"] isKindOfClass:NSString.class] ? record[@"text"] : @"";
  NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
  for (NSDictionary *span in NFBRichTextSpans(text, record[@"facets"])) {
    NSRange range = [span[@"range"] rangeValue];
    NSString *token = [text substringWithRange:range], *display = token;
    NSURL *url = NFBURLForFacetFeature(span[@"feature"], token, shortenURLs ? &display : NULL);
    if (url) [entries addObject:@{@"range":span[@"range"], @"display":display, @"url":url}];
  }

  NSMutableString *displayText = [NSMutableString string];
  NSMutableArray<NSDictionary *> *links = [NSMutableArray array];
  NSUInteger cursor = 0;
  for (NSDictionary *entry in entries) {
    NSRange originalRange = [entry[@"range"] rangeValue];
    if (originalRange.location < cursor || NSMaxRange(originalRange) > text.length) continue;
    [displayText appendString:[text substringWithRange:NSMakeRange(cursor, originalRange.location - cursor)]];
    NSString *replacement = [entry[@"display"] isKindOfClass:NSString.class] ? entry[@"display"] : [text substringWithRange:originalRange];
    NSRange visibleRange = NSMakeRange(displayText.length, replacement.length);
    [displayText appendString:replacement];
    NSURL *url = [entry[@"url"] isKindOfClass:NSURL.class] ? entry[@"url"] : nil;
    if (url) [links addObject:@{@"range": [NSValue valueWithRange:visibleRange], @"url": url}];
    cursor = NSMaxRange(originalRange);
  }
  if (cursor < text.length) [displayText appendString:[text substringFromIndex:cursor]];
  return @{@"text": displayText ?: text, @"links": links};
}

static void NFBApplyTweetLink(NSMutableAttributedString *attributed, NSURL *url, NSRange range) {
  if (!url || range.location == NSNotFound || NSMaxRange(range) > attributed.length || range.length == 0) return;
  [attributed addAttributes:@{
    NSForegroundColorAttributeName: NFBColorAccent(),
    NFBTextLinkURLAttributeName: url
  } range:range];
}

UIImage *NFBTwemojiImageForEmoji(NSString *emoji) {
  (void)emoji;
  return nil;
}

NSAttributedString *NFBAttributedStringByReplacingEmojiWithTwemoji(NSAttributedString *attributed, UIFont *font) {
  (void)font;
  return attributed ?: [[NSAttributedString alloc] initWithString:@""];
}

static NSAttributedString *NFBTweetBodyAttributedStringWithDisplay(NSString *text, NSArray<NSDictionary *> *links, UIFont *font) {
  NSString *safeText = text ?: @"";
  UIFont *resolvedFont = font ?: NFBFont(15.0, NFBFontWeightRegular);
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.lineSpacing = 1.0;
  style.minimumLineHeight = ceil(resolvedFont.lineHeight);
  style.lineBreakMode = NSLineBreakByWordWrapping;
  NSDictionary *attributes = @{
    NSFontAttributeName: resolvedFont,
    NSForegroundColorAttributeName: NFBColorText(),
    NSParagraphStyleAttributeName: style
  };
  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:safeText attributes:attributes];
  if (safeText.length == 0) return attributed;

  for (NSDictionary *link in links ?: @[]) {
    NSValue *rangeValue = [link[@"range"] isKindOfClass:NSValue.class] ? link[@"range"] : nil;
    NSURL *url = [link[@"url"] isKindOfClass:NSURL.class] ? link[@"url"] : nil;
    if (!rangeValue || !url) continue;
    NFBApplyTweetLink(attributed, url, rangeValue.rangeValue);
  }

  return NFBAttributedStringByReplacingEmojiWithTwemoji(attributed, resolvedFont);
}

NSAttributedString *NFBTweetBodyAttributedString(NSString *text, UIFont *font) {
  NSDictionary *display = NFBDisplayTextAndLinksForRecord(@{@"text":text ?: @""}, YES);
  return NFBTweetBodyAttributedStringWithDisplay(display[@"text"], display[@"links"], font);
}

NSAttributedString *NFBTweetBodyAttributedStringForPost(NSDictionary *post, UIFont *font) {
  NSDictionary *display = NFBDisplayTextAndLinksForRecord(NFBPostDisplayRecord(post ?: @{}), YES);
  return NFBTweetBodyAttributedStringWithDisplay(display[@"text"], display[@"links"], font);
}

NSAttributedString *NFBMessageBodyAttributedString(NSDictionary *record, UIFont *font) {
  NSDictionary *display = NFBDisplayTextAndLinksForRecord(record ?: @{}, NO);
  return NFBTweetBodyAttributedStringWithDisplay(display[@"text"], display[@"links"], font);
}

NSAttributedString *NFBComposerTextAttributedString(NSString *text, UIFont *font) {
  NSString *safeText = text ?: @"";
  UIFont *resolvedFont = font ?: NFBFont(NFBIPAMetricValue(NFBIPAMetricComposerBodyFontSize), NFBFontWeightRegular);
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.lineSpacing = 1.0;
  style.minimumLineHeight = ceil(resolvedFont.lineHeight);
  style.lineBreakMode = NSLineBreakByWordWrapping;
  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:safeText attributes:@{
    NSFontAttributeName: resolvedFont,
    NSForegroundColorAttributeName: NFBColorText(),
    NSParagraphStyleAttributeName: style
  }];
  if (safeText.length == 0) return attributed;

  UIColor *accent = NFBColorAccent();
  for (NSDictionary *span in NFBRichTextSpans(safeText, nil)) {
    [attributed addAttribute:NSForegroundColorAttributeName value:accent range:[span[@"range"] rangeValue]];
  }
  return attributed;
}

@implementation NFBInteractiveTextLabel

- (void)nfb_invalidateTextLayout {
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout];
}

- (NSAttributedString *)nfb_layoutAttributedText {
  NSAttributedString *attributedText = self.attributedText;
  if (attributedText.length > 0) return attributedText;
  NSString *text = self.text ?: @"";
  if (text.length == 0) return nil;
  UIFont *font = self.font ?: NFBFont(15.0, NFBFontWeightRegular);
  return [[NSAttributedString alloc] initWithString:text attributes:@{
    NSFontAttributeName: font,
    NSForegroundColorAttributeName: self.textColor ?: NFBColorText()
  }];
}

- (CGSize)nfb_textLayoutSizeForWidth:(CGFloat)width {
  NSAttributedString *source = [self nfb_layoutAttributedText];
  if (source.length == 0 || width <= 0.0 || width == CGFLOAT_MAX) return [super sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];

  NSMutableAttributedString *layoutText = [source mutableCopy];
  NSRange fullRange = NSMakeRange(0, layoutText.length);
  UIFont *font = self.font ?: NFBFont(15.0, NFBFontWeightRegular);
  if (![layoutText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil]) {
    [layoutText addAttribute:NSFontAttributeName value:font range:fullRange];
  }

  NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:layoutText];
  NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
  NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:CGSizeMake(width, CGFLOAT_MAX)];
  textContainer.lineFragmentPadding = 0.0;
  textContainer.maximumNumberOfLines = self.numberOfLines;
  textContainer.lineBreakMode = self.lineBreakMode;
  [layoutManager addTextContainer:textContainer];
  [textStorage addLayoutManager:layoutManager];
  [layoutManager glyphRangeForTextContainer:textContainer];

  CGRect usedRect = [layoutManager usedRectForTextContainer:textContainer];
  CGFloat measuredHeight = ceil(CGRectGetHeight(usedRect));
  CGFloat measuredWidth = ceil(CGRectGetWidth(usedRect));
  CGFloat minimumHeight = ceil(font.lineHeight);
  CGFloat height = MAX(minimumHeight, measuredHeight) + (1.0 / UIScreen.mainScreen.scale);
  return CGSizeMake(MIN(width, MAX(0.0, measuredWidth)), height);
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.userInteractionEnabled = YES;
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    self.userInteractionEnabled = YES;
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  if (self.numberOfLines != 1) {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width > 0.0 && fabs(self.preferredMaxLayoutWidth - width) > 0.5) {
      self.preferredMaxLayoutWidth = width;
      [self invalidateIntrinsicContentSize];
    }
  }
}

- (CGSize)intrinsicContentSize {
  if (self.numberOfLines != 1) {
    CGFloat width = self.preferredMaxLayoutWidth > 0.0 ? self.preferredMaxLayoutWidth : CGRectGetWidth(self.bounds);
    if (width > 0.0) {
      CGSize size = [self nfb_textLayoutSizeForWidth:width];
      return CGSizeMake(UIViewNoIntrinsicMetric, size.height);
    }
  }
  return [super intrinsicContentSize];
}

- (CGSize)sizeThatFits:(CGSize)size {
  if (self.numberOfLines != 1 && size.width > 0.0 && size.width != CGFLOAT_MAX) {
    return [self nfb_textLayoutSizeForWidth:size.width];
  }
  return [super sizeThatFits:size];
}

- (void)setText:(NSString *)text {
  [super setText:text];
  [self nfb_invalidateTextLayout];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
  [super setAttributedText:attributedText];
  [self nfb_invalidateTextLayout];
}

- (void)setFont:(UIFont *)font {
  [super setFont:font];
  [self nfb_invalidateTextLayout];
}

- (void)setNumberOfLines:(NSInteger)numberOfLines {
  [super setNumberOfLines:numberOfLines];
  [self nfb_invalidateTextLayout];
}

- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode {
  [super setLineBreakMode:lineBreakMode];
  [self nfb_invalidateTextLayout];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  if (![super pointInside:point withEvent:event]) return NO;
  if (self.plainTapHandler) return YES;
  return [self linkURLAtPoint:point] != nil;
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
  UITouch *touch = touches.anyObject;
  NSURL *url = touch ? [self linkURLAtPoint:[touch locationInView:self]] : nil;
  if (url && self.linkTapHandler) {
    self.linkTapHandler(url);
    return;
  }
  if (self.plainTapHandler) {
    self.plainTapHandler();
    return;
  }
  [super touchesEnded:touches withEvent:event];
}

- (NSURL *)linkURLAtPoint:(CGPoint)point {
  NSAttributedString *attributedText = self.attributedText;
  if (attributedText.length == 0 || CGRectIsEmpty(self.bounds)) return nil;
  NSMutableAttributedString *layoutText = [attributedText mutableCopy];
  NSRange fullRange = NSMakeRange(0, layoutText.length);
  if (![layoutText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil]) {
    [layoutText addAttribute:NSFontAttributeName value:self.font ?: NFBFont(15.0, NFBFontWeightRegular) range:fullRange];
  }

  NSTextStorage *textStorage = [[NSTextStorage alloc] initWithAttributedString:layoutText];
  NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
  NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:self.bounds.size];
  textContainer.lineFragmentPadding = 0.0;
  textContainer.maximumNumberOfLines = self.numberOfLines;
  textContainer.lineBreakMode = self.lineBreakMode;
  [layoutManager addTextContainer:textContainer];
  [textStorage addLayoutManager:layoutManager];

  CGRect usedRect = [layoutManager usedRectForTextContainer:textContainer];
  CGFloat xOffset = -usedRect.origin.x;
  if (self.textAlignment == NSTextAlignmentCenter) {
    xOffset += floor((CGRectGetWidth(self.bounds) - CGRectGetWidth(usedRect)) * 0.5);
  } else if (self.textAlignment == NSTextAlignmentRight) {
    xOffset += CGRectGetWidth(self.bounds) - CGRectGetWidth(usedRect);
  }
  CGFloat yOffset = floor((CGRectGetHeight(self.bounds) - CGRectGetHeight(usedRect)) * 0.5) - usedRect.origin.y;
  CGPoint textPoint = CGPointMake(point.x - xOffset, point.y - yOffset);
  if (textPoint.x < 0.0 || textPoint.y < 0.0 || textPoint.x > textContainer.size.width || textPoint.y > textContainer.size.height) return nil;

  CGFloat fraction = 0.0;
  NSUInteger glyphIndex = [layoutManager glyphIndexForPoint:textPoint inTextContainer:textContainer fractionOfDistanceThroughGlyph:&fraction];
  if (glyphIndex >= layoutManager.numberOfGlyphs) return nil;
  CGRect glyphRect = [layoutManager boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1) inTextContainer:textContainer];
  if (!CGRectContainsPoint(CGRectInset(glyphRect, -6.0, -6.0), textPoint)) return nil;
  NSUInteger characterIndex = [layoutManager characterIndexForGlyphAtIndex:glyphIndex];
  if (characterIndex >= attributedText.length) return nil;
  id value = [attributedText attribute:NFBTextLinkURLAttributeName atIndex:characterIndex effectiveRange:nil];
  if (!value) value = [attributedText attribute:NSLinkAttributeName atIndex:characterIndex effectiveRange:nil];
  if ([value isKindOfClass:NSURL.class]) return value;
  if ([value isKindOfClass:NSString.class]) return [NSURL URLWithString:value];
  return nil;
}

@end

UIImage *NFBBundledImage(NSString *directory, NSString *name, NSString *extension) {
  NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:extension inDirectory:directory];
  if (!path) return [UIImage imageNamed:name];
  return [UIImage imageWithContentsOfFile:path];
}

static CGFloat NFBTemplateIconPointSize(NSString *name) {
  if ([name hasPrefix:@"nfb_tab_"]) return 24.0;
  if ([name isEqualToString:@"nfb_arrow_left"]) return 28.0;
  if ([name isEqualToString:@"nfb_twitter_logo"]) return 30.0;
  if ([name isEqualToString:@"nfb_compose"]) return 28.0;
  if ([name isEqualToString:@"nfb_loading"]) return 28.0;
  if ([name isEqualToString:@"nfb_more"]) return 22.0;
  if ([name isEqualToString:@"nfb_dark_mode_off"] || [name isEqualToString:@"nfb_dark_mode_on"]) return 25.0;
  return 24.0;
}

static UIImage *NFBImageWithPointSize(UIImage *image, CGFloat pointSize) {
  if (!image) return nil;
  CGSize size = CGSizeMake(pointSize, pointSize);
  UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
  [image drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
  UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return resized ?: image;
}

UIImage *NFBTemplateIcon(NSString *name) {
  UIImage *image = NFBBundledImage(@"GeneratedIcons", name, @"png");
  image = NFBImageWithPointSize(image, NFBTemplateIconPointSize(name));
  return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *NFBVerifiedBadgeImage(void) {
  // The IPA's vector uses a transparent check cutout so it works in all themes.
  return [NFBTemplateIcon(@"nfb_verified") imageWithTintColor:NFBColorAccent()
                                             renderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *NFBDefaultAvatarImage(void) {
  return NFBBundledImage(@"TwitterCloneAssets", @"twitter-default-egg", @"png") ?: NFBBrandIconImage();
}

UIImage *NFBDefaultCoverImage(void) {
  return NFBBundledImage(@"TwitterCloneAssets", @"twitter-default-cover", @"png");
}

UIImage *NFBBrandIconImage(void) {
  UIImage *image = NFBBundledImage(@"NeoFreeBirdBranding", @"Icon_rounded", @"png");
  return image ?: [UIImage imageNamed:@"Icon_rounded"];
}

UIImage *NFBLoadingImage(void) {
  return NFBTemplateIcon(@"nfb_loading");
}

static void NFBApplyTombstoneTextAppearance(UILabel *titleLabel, UILabel *subtitleLabel, CGFloat titleSize, CGFloat subtitleSize) {
  titleLabel.font = NFBFont(titleSize, NFBFontWeightRegular);
  titleLabel.textColor = NFBColorSecondaryText();
  titleLabel.numberOfLines = 0;
  titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
  titleLabel.textAlignment = NSTextAlignmentLeft;
  subtitleLabel.font = NFBFont(subtitleSize, NFBFontWeightRegular);
  subtitleLabel.textColor = NFBColorSecondaryText();
  subtitleLabel.numberOfLines = 0;
  subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;
  subtitleLabel.textAlignment = NSTextAlignmentLeft;
}

void NFBApplyTombstoneAppearance(UIView *container, UILabel *titleLabel, UILabel *subtitleLabel, CGFloat titleSize, CGFloat subtitleSize) {
  container.backgroundColor = UIColor.clearColor;
  container.layer.cornerRadius = 0.0;
  container.layer.borderWidth = 0.0;
  container.layer.borderColor = UIColor.clearColor.CGColor;
  container.clipsToBounds = NO;
  NFBApplyTombstoneTextAppearance(titleLabel, subtitleLabel, titleSize, subtitleSize);
}

void NFBApplyFramedTombstoneAppearance(UIView *container, UILabel *titleLabel, UILabel *subtitleLabel, CGFloat titleSize, CGFloat subtitleSize) {
  container.backgroundColor = NFBTwitterCloneSidebarBackgroundColor();
  container.layer.cornerRadius = 3.0;
  container.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  container.layer.borderColor = NFBTwitterCloneTombstoneBorderColor().CGColor;
  container.clipsToBounds = YES;
  NFBApplyTombstoneTextAppearance(titleLabel, subtitleLabel, titleSize, subtitleSize);
}

@interface NFBPullRefreshControl : UIRefreshControl
@property (nonatomic, strong) UIImageView *arrowView;
@property (nonatomic, strong) UIImageView *loadingView;
- (void)updateRefreshChrome;
@end

@implementation NFBPullRefreshControl

- (instancetype)init {
  self = [super init];
  if (self) {
    self.tintColor = UIColor.clearColor;
    self.clipsToBounds = YES;

    _arrowView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_arrow_left")];
    _arrowView.tintColor = NFBColorAccent();
    _arrowView.contentMode = UIViewContentModeScaleAspectFit;
    _arrowView.transform = CGAffineTransformMakeRotation((CGFloat)-M_PI_2);
    _arrowView.alpha = 0.0;
    _arrowView.layer.shadowColor = UIColor.blackColor.CGColor;
    _arrowView.layer.shadowOpacity = 0.18;
    _arrowView.layer.shadowRadius = 2.0;
    _arrowView.layer.shadowOffset = CGSizeZero;
    [self addSubview:_arrowView];

    _loadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    _loadingView.tintColor = NFBColorAccent();
    _loadingView.contentMode = UIViewContentModeScaleAspectFit;
    _loadingView.hidden = YES;
    [self addSubview:_loadingView];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  [self updateRefreshChrome];
}

- (void)beginRefreshing {
  [super beginRefreshing];
  [self updateRefreshChrome];
}

- (void)endRefreshing {
  [super endRefreshing];
  NFBStopLoadingAnimation(self.loadingView);
  self.loadingView.hidden = YES;
  self.arrowView.alpha = 0.0;
}

- (UIScrollView *)containingScrollView {
  UIView *view = self.superview;
  while (view) {
    if ([view isKindOfClass:UIScrollView.class]) return (UIScrollView *)view;
    view = view.superview;
  }
  return nil;
}

- (void)updateRefreshChrome {
  self.tintColor = UIColor.clearColor;
  self.layer.zPosition = 0.0;
  self.clipsToBounds = YES;
  self.arrowView.tintColor = NFBColorAccent();
  self.loadingView.tintColor = NFBColorAccent();

  CGFloat pullHeight = MAX(CGRectGetHeight(self.bounds), 1.0);
  CGFloat visible = MIN(1.0, MAX(0.0, pullHeight / 54.0));
  CGFloat side = 21.0;
  CGFloat midX = CGRectGetMidX(self.bounds);
  CGFloat y = floor(MAX(18.0, pullHeight - 18.0));
  CGRect frame = CGRectMake(midX - side / 2.0, y - side / 2.0, side, side);
  self.arrowView.frame = frame;
  self.loadingView.frame = frame;
  [self bringSubviewToFront:self.arrowView];
  [self bringSubviewToFront:self.loadingView];

  if (self.refreshing) {
    self.arrowView.alpha = 0.0;
    NFBStartLoadingAnimation(self.loadingView);
  } else {
    NFBStopLoadingAnimation(self.loadingView);
    self.loadingView.hidden = YES;
    UIScrollView *scrollView = [self containingScrollView];
    BOOL activelyPulling = scrollView.tracking || scrollView.dragging;
    self.arrowView.alpha = activelyPulling ? visible : 0.0;
    CGFloat turnProgress = MIN(1.0, MAX(0.0, (visible - 0.62) / 0.38));
    self.arrowView.transform = CGAffineTransformMakeRotation((CGFloat)(-M_PI_2 + M_PI * turnProgress));
  }
}

@end

UIRefreshControl *NFBCreateRefreshControl(id target, SEL action) {
  UIRefreshControl *refreshControl = [[NFBPullRefreshControl alloc] init];
  [refreshControl addTarget:target action:action forControlEvents:UIControlEventValueChanged];
  return refreshControl;
}

void NFBUpdateRefreshControlAppearance(UIRefreshControl *refreshControl) {
  if (!refreshControl) return;
  if ([refreshControl isKindOfClass:NFBPullRefreshControl.class]) {
    [(NFBPullRefreshControl *)refreshControl updateRefreshChrome];
  } else {
    refreshControl.tintColor = NFBColorAccent();
  }
}

UIView *NFBTitleView(NSString *title, NSString *subtitle) {
  UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 240.0, 44.0)];
  container.backgroundColor = UIColor.clearColor;

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentCenter;
  stack.distribution = UIStackViewDistributionEqualCentering;
  stack.spacing = 0.0;

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.text = title;
  titleLabel.textColor = NFBColorText();
  titleLabel.font = NFBFont(17.0, NFBFontWeightHeavy);
  titleLabel.textAlignment = NSTextAlignmentCenter;
  titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  [stack addArrangedSubview:titleLabel];

  if (subtitle.length > 0) {
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.text = subtitle;
    subtitleLabel.textColor = NFBColorSecondaryText();
    subtitleLabel.font = NFBFont(12.0, NFBFontWeightRegular);
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    subtitleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [stack addArrangedSubview:subtitleLabel];
  }

  [container addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [stack.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
    [stack.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
    [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:container.leadingAnchor],
    [stack.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor],
    [titleLabel.widthAnchor constraintLessThanOrEqualToConstant:220.0]
  ]];

  return container;
}

UIBarButtonItem *NFBBackBarButtonItem(id target, SEL action) {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
  button.frame = CGRectMake(0.0, 0.0, 44.0, 44.0);
  button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 0.0, 8.0, 16.0);
  [button setImage:NFBTemplateIcon(@"nfb_arrow_left") forState:UIControlStateNormal];
  button.accessibilityLabel = @"Back";
  [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
  return [[UIBarButtonItem alloc] initWithCustomView:button];
}

void NFBStartLoadingAnimation(UIImageView *imageView) {
  if (!imageView) return;
  imageView.hidden = NO;
  imageView.alpha = 1.0;
  if (![imageView.layer animationForKey:@"nfb.loading.rotation"]) {
    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = @0.0;
    rotation.toValue = @(M_PI * 2.0);
    rotation.duration = 0.78;
    rotation.repeatCount = HUGE_VALF;
    rotation.removedOnCompletion = NO;
    [imageView.layer addAnimation:rotation forKey:@"nfb.loading.rotation"];
  }
  if (![imageView.layer animationForKey:@"nfb.loading.opacity"]) {
    CABasicAnimation *opacity = [CABasicAnimation animationWithKeyPath:@"opacity"];
    opacity.fromValue = @0.62;
    opacity.toValue = @1.0;
    opacity.duration = 0.52;
    opacity.autoreverses = YES;
    opacity.repeatCount = HUGE_VALF;
    opacity.removedOnCompletion = NO;
    [imageView.layer addAnimation:opacity forKey:@"nfb.loading.opacity"];
  }
}

void NFBStopLoadingAnimation(UIImageView *imageView) {
  [imageView.layer removeAnimationForKey:@"nfb.loading.rotation"];
  [imageView.layer removeAnimationForKey:@"nfb.loading.opacity"];
  imageView.alpha = 1.0;
}

static NSMutableDictionary<NSString *, NSNumber *> *NFBSoundCache(void) {
  static NSMutableDictionary<NSString *, NSNumber *> *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [NSMutableDictionary dictionary];
  });
  return cache;
}

static NSURL *NFBSoundURLForName(NSString *fileName) {
  if (fileName.length == 0) return nil;
  NSString *baseName = fileName.stringByDeletingPathExtension;
  NSString *extension = fileName.pathExtension;
  if (baseName.length == 0) return nil;
  if (extension.length > 0) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:baseName withExtension:extension subdirectory:@"TwitterSounds"];
    if (url) return url;
  }
  for (NSString *candidateExtension in @[@"aac", @"m4a", @"caf", @"wav"]) {
    NSURL *url = [[NSBundle mainBundle] URLForResource:baseName withExtension:candidateExtension subdirectory:@"TwitterSounds"];
    if (url) return url;
  }
  return nil;
}

void NFBPlaySound(NSString *fileName) {
  NSURL *url = NFBSoundURLForName(fileName);
  if (!url) return;
  NSMutableDictionary<NSString *, NSNumber *> *cache = NFBSoundCache();
  NSNumber *cached = cache[fileName];
  SystemSoundID soundID = (SystemSoundID)cached.unsignedIntValue;
  if (soundID == 0) {
    OSStatus status = AudioServicesCreateSystemSoundID((__bridge CFURLRef)url, &soundID);
    if (status != kAudioServicesNoError || soundID == 0) return;
    cache[fileName] = @(soundID);
  }
  AudioServicesPlaySystemSound(soundID);
}

void NFBApplyNavigationAppearance(UINavigationController *navigationController) {
  NFBObserveAppearance(navigationController, ^(id owner) { NFBApplyNavigationAppearance(owner); });
  navigationController.navigationBar.prefersLargeTitles = NO;
  navigationController.navigationBar.tintColor = NFBColorText();
  navigationController.navigationBar.translucent = NO;
  UIImage *backImage = NFBTemplateIcon(@"nfb_arrow_left");
  navigationController.navigationBar.backIndicatorImage = backImage;
  navigationController.navigationBar.backIndicatorTransitionMaskImage = backImage;
  for (UIViewController *viewController in navigationController.viewControllers) {
    viewController.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@""
                                                                                       style:UIBarButtonItemStylePlain
                                                                                      target:nil
                                                                                      action:nil];
    if (@available(iOS 14.0, *)) {
      viewController.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }
  }

  if (NSClassFromString(@"UINavigationBarAppearance")) {
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = NFBColorBackground();
    appearance.shadowColor = NFBColorBorder();
    appearance.titleTextAttributes = @{
      NSForegroundColorAttributeName: NFBColorText(),
      NSFontAttributeName: NFBFont(17.0, NFBFontWeightHeavy)
    };
    appearance.largeTitleTextAttributes = @{
      NSForegroundColorAttributeName: NFBColorText(),
      NSFontAttributeName: NFBFont(30.0, NFBFontWeightHeavy)
    };
    navigationController.navigationBar.standardAppearance = appearance;
    navigationController.navigationBar.scrollEdgeAppearance = appearance;
    navigationController.navigationBar.compactAppearance = appearance;
  } else {
    navigationController.navigationBar.barTintColor = NFBColorBackground();
    navigationController.navigationBar.titleTextAttributes = @{
      NSForegroundColorAttributeName: NFBColorText(),
      NSFontAttributeName: NFBFont(17.0, NFBFontWeightHeavy)
    };
  }
}

void NFBApplyDarkNavigationAppearance(UINavigationController *navigationController) {
  NFBObserveAppearance(navigationController, ^(id owner) { NFBApplyDarkNavigationAppearance(owner); });
  navigationController.navigationBar.prefersLargeTitles = NO;
  navigationController.navigationBar.tintColor = NFBIPAOnMediaPrimaryTextColor();
  navigationController.navigationBar.translucent = NO;
  UIImage *backImage = NFBTemplateIcon(@"nfb_arrow_left");
  navigationController.navigationBar.backIndicatorImage = backImage;
  navigationController.navigationBar.backIndicatorTransitionMaskImage = backImage;
  for (UIViewController *viewController in navigationController.viewControllers) {
    viewController.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@""
                                                                                       style:UIBarButtonItemStylePlain
                                                                                      target:nil
                                                                                      action:nil];
    if (@available(iOS 14.0, *)) {
      viewController.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }
  }

  if (NSClassFromString(@"UINavigationBarAppearance")) {
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = NFBIPAOnMediaBarBackgroundColor();
    appearance.shadowColor = NFBIPAOnMediaSeparatorColor();
    appearance.titleTextAttributes = @{
      NSForegroundColorAttributeName: NFBIPAOnMediaPrimaryTextColor(),
      NSFontAttributeName: NFBFont(17.0, NFBFontWeightHeavy)
    };
    appearance.largeTitleTextAttributes = @{
      NSForegroundColorAttributeName: NFBIPAOnMediaPrimaryTextColor(),
      NSFontAttributeName: NFBFont(30.0, NFBFontWeightHeavy)
    };
    navigationController.navigationBar.standardAppearance = appearance;
    navigationController.navigationBar.scrollEdgeAppearance = appearance;
    navigationController.navigationBar.compactAppearance = appearance;
  } else {
    navigationController.navigationBar.barTintColor = NFBIPAOnMediaBarBackgroundColor();
    navigationController.navigationBar.titleTextAttributes = @{
      NSForegroundColorAttributeName: NFBIPAOnMediaPrimaryTextColor(),
      NSFontAttributeName: NFBFont(17.0, NFBFontWeightHeavy)
    };
  }
}

void NFBApplyTabBarAppearance(UITabBar *tabBar) {
  NFBObserveAppearance(tabBar, ^(id owner) { NFBApplyTabBarAppearance(owner); });
  tabBar.tintColor = NFBNeoFreeBirdTabBarSelectedTintColor();
  tabBar.unselectedItemTintColor = NFBNeoFreeBirdTabBarNormalTintColor();
  tabBar.barTintColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);
  tabBar.backgroundColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);
  tabBar.opaque = YES;
  tabBar.itemPositioning = UITabBarItemPositioningFill;
  tabBar.backgroundImage = [UIImage new];
  tabBar.shadowImage = [UIImage new];
  tabBar.translucent = NO;

  if (NSClassFromString(@"UITabBarAppearance")) {
    UITabBarAppearance *appearance = NFBConfiguredTabBarAppearance();
    tabBar.standardAppearance = appearance;
    if ([tabBar respondsToSelector:@selector(setScrollEdgeAppearance:)]) {
      [tabBar setValue:appearance forKey:@"scrollEdgeAppearance"];
    }
  }
}

void NFBApplyAppAppearance(UIWindow *window) {
  NFBRegisterBundledFonts();
  NFBApplyNeoFreeBirdFirstRunDefaults();
  window.tintColor = NFBColorAccent();
  if ([window respondsToSelector:@selector(setOverrideUserInterfaceStyle:)]) {
    window.overrideUserInterfaceStyle = NFBCurrentUserInterfaceStyle();
  }

  [UITabBar appearance].tintColor = NFBNeoFreeBirdTabBarSelectedTintColor();
  [UITabBar appearance].unselectedItemTintColor = NFBNeoFreeBirdTabBarNormalTintColor();
  [UITabBar appearance].barTintColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);
  [UITabBar appearance].backgroundColor = NFBIPAColor(NFBIPAColorRoleTabBarBackground);
  [UITabBar appearance].backgroundImage = [UIImage new];
  [UITabBar appearance].shadowImage = [UIImage new];
  [UITabBar appearance].translucent = NO;

  if (NSClassFromString(@"UITabBarAppearance")) {
    UITabBarAppearance *appearance = NFBConfiguredTabBarAppearance();
    [UITabBar appearance].standardAppearance = appearance;
    if ([[UITabBar appearance] respondsToSelector:@selector(setScrollEdgeAppearance:)]) {
      [[UITabBar appearance] setValue:appearance forKey:@"scrollEdgeAppearance"];
    }
  }
}

static UIColor *NFBRefreshedThemeColor(UIColor *color) {
  NSNumber *role = color ? objc_getAssociatedObject(color, &NFBThemeColorRoleKey) : nil;
  return role ? NFBIPAColor(role.integerValue) : color;
}

static NSDictionary *NFBRefreshedTextAttributes(NSDictionary *attributes) {
  NSMutableDictionary *result = nil;
  for (NSString *key in @[NSForegroundColorAttributeName, NSBackgroundColorAttributeName, NSStrokeColorAttributeName]) {
    UIColor *color = attributes[key];
    if (![color isKindOfClass:UIColor.class]) continue;
    UIColor *updated = NFBRefreshedThemeColor(color);
    if (updated != color) {
      if (!result) result = [attributes mutableCopy];
      result[key] = updated;
    }
  }
  return result ?: attributes;
}

static NSAttributedString *NFBRefreshedAttributedText(NSAttributedString *text) {
  if (!text.length) return text;
  __block NSMutableAttributedString *result = nil;
  [text enumerateAttributesInRange:NSMakeRange(0, text.length) options:0 usingBlock:^(NSDictionary *attributes, NSRange range, BOOL *stop) {
    NSDictionary *updated = NFBRefreshedTextAttributes(attributes);
    if (updated != attributes) {
      if (!result) result = [text mutableCopy];
      [result setAttributes:updated range:range];
    }
  }];
  return result ?: text;
}

static void NFBRefreshViewTheme(UIView *view) {
  if (!view) return;
  UIColor *color = NFBRefreshedThemeColor(view.backgroundColor);
  if (color != view.backgroundColor) view.backgroundColor = color;
  color = NFBRefreshedThemeColor(view.tintColor);
  if (color != view.tintColor) view.tintColor = color;
  if ([view isKindOfClass:UILabel.class]) {
    UILabel *label = (UILabel *)view;
    NSAttributedString *text = NFBRefreshedAttributedText(label.attributedText);
    color = NFBRefreshedThemeColor(label.textColor);
    if (color != label.textColor) label.textColor = color;
    color = NFBRefreshedThemeColor(label.highlightedTextColor);
    if (color != label.highlightedTextColor) label.highlightedTextColor = color;
    if (text != label.attributedText) label.attributedText = text;
  }
  if ([view isKindOfClass:UIButton.class]) {
    UIButton *button = (UIButton *)view;
    for (NSNumber *stateNumber in @[@(UIControlStateNormal), @(UIControlStateHighlighted), @(UIControlStateSelected), @(UIControlStateDisabled)]) {
      UIControlState state = stateNumber.unsignedIntegerValue;
      UIColor *original = [button titleColorForState:state];
      color = NFBRefreshedThemeColor(original);
      if (color != original) [button setTitleColor:color forState:state];
      NSAttributedString *title = [button attributedTitleForState:state];
      NSAttributedString *updated = NFBRefreshedAttributedText(title);
      if (updated != title) [button setAttributedTitle:updated forState:state];
    }
  }
  if ([view isKindOfClass:UITextField.class]) {
    UITextField *field = (UITextField *)view;
    color = NFBRefreshedThemeColor(field.textColor);
    if (color != field.textColor) field.textColor = color;
    NSAttributedString *placeholder = NFBRefreshedAttributedText(field.attributedPlaceholder);
    if (placeholder != field.attributedPlaceholder) field.attributedPlaceholder = placeholder;
    if (field.isFirstResponder) [field reloadInputViews];
  }
  if ([view isKindOfClass:UITextView.class]) {
    UITextView *textView = (UITextView *)view;
    // Preserve attributed links, selection, typing style and active IME input.
    if (!textView.markedTextRange) {
      NSAttributedString *text = NFBRefreshedAttributedText(textView.attributedText);
      NSDictionary *typingAttributes = NFBRefreshedTextAttributes(textView.typingAttributes);
      NSRange selection = textView.selectedRange;
      color = NFBRefreshedThemeColor(textView.textColor);
      if (color != textView.textColor) textView.textColor = color;
      if (text != textView.attributedText) {
        textView.attributedText = text;
        textView.selectedRange = selection;
      }
      textView.typingAttributes = typingAttributes;
      textView.linkTextAttributes = NFBRefreshedTextAttributes(textView.linkTextAttributes);
    }
    if (textView.isFirstResponder) [textView reloadInputViews];
  }
  if ([view isKindOfClass:UIScrollView.class]) {
    ((UIScrollView *)view).indicatorStyle = NFBCurrentUserInterfaceStyle() == UIUserInterfaceStyleLight ? UIScrollViewIndicatorStyleBlack : UIScrollViewIndicatorStyleWhite;
  }
  if ([view isKindOfClass:UISwitch.class]) {
    UISwitch *control = (UISwitch *)view;
    control.onTintColor = NFBRefreshedThemeColor(control.onTintColor);
    control.thumbTintColor = NFBRefreshedThemeColor(control.thumbTintColor);
  }
  if ([view isKindOfClass:UISlider.class]) {
    UISlider *control = (UISlider *)view;
    control.minimumTrackTintColor = NFBRefreshedThemeColor(control.minimumTrackTintColor);
    control.maximumTrackTintColor = NFBRefreshedThemeColor(control.maximumTrackTintColor);
    control.thumbTintColor = NFBRefreshedThemeColor(control.thumbTintColor);
  }
  if ([view isKindOfClass:UIActivityIndicatorView.class]) {
    UIActivityIndicatorView *indicator = (UIActivityIndicatorView *)view;
    indicator.color = NFBRefreshedThemeColor(indicator.color);
  }
  if ([view isKindOfClass:UIProgressView.class]) {
    UIProgressView *progress = (UIProgressView *)view;
    progress.progressTintColor = NFBRefreshedThemeColor(progress.progressTintColor);
    progress.trackTintColor = NFBRefreshedThemeColor(progress.trackTintColor);
  }
  for (UIView *child in view.subviews) NFBRefreshViewTheme(child);
  [view setNeedsDisplay];
}

static void NFBRefreshControllerTheme(UIViewController *controller, NSHashTable *visited) {
  if (!controller || [visited containsObject:controller]) return;
  [visited addObject:controller];
  // Do not load offscreen controllers or discard navigation, input or scroll state.
  if (controller.isViewLoaded) NFBRefreshViewTheme(controller.view);
  NFBRefreshViewTheme(controller.navigationItem.titleView);
  NSMutableArray *items = [NSMutableArray arrayWithArray:controller.navigationItem.leftBarButtonItems ?: @[]];
  [items addObjectsFromArray:controller.navigationItem.rightBarButtonItems ?: @[]];
  for (UIBarButtonItem *item in items) {
    item.tintColor = NFBRefreshedThemeColor(item.tintColor);
    NFBRefreshViewTheme(item.customView);
  }
  [controller setNeedsStatusBarAppearanceUpdate];
  for (UIViewController *child in controller.childViewControllers) NFBRefreshControllerTheme(child, visited);
  NFBRefreshControllerTheme(controller.presentedViewController, visited);
}

void NFBApplyThemeToVisibleWindows(void) {
  UIApplication *application = UIApplication.sharedApplication;
  NSMutableOrderedSet<UIWindow *> *windows = [NSMutableOrderedSet orderedSet];
  // This app uses UIApplicationDelegate.window and has no scene manifest.
  // Include legacy windows even on iOS 13+, as well as any scene windows.
  [windows addObjectsFromArray:application.windows];
  if ([application.delegate respondsToSelector:@selector(window)] && application.delegate.window) {
    [windows addObject:application.delegate.window];
  }
  for (UIScene *scene in application.connectedScenes) {
    if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
  }
  NSHashTable *visited = [NSHashTable weakObjectsHashTable];
  for (UIWindow *window in windows) {
    NFBApplyAppAppearance(window);
    NFBRefreshControllerTheme(window.rootViewController, visited);
  }
}
