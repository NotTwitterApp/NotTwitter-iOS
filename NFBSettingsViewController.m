#import "NFBSettingsViewController.h"

#import "NFBAtprotoClient.h"
#import "NFBAtprotoSession.h"
#import "NFBDisplaySettingsViewController.h"
#import "NFBModeration.h"
#import "NFBTheme.h"

static NSString * const NFBLastSelectedAppIconKey = @"bh_last_selected_app_icon";
static NSString * const NFBHideBskySocialSuffixKey = @"bh_hide_bsky_social_suffix";
static NSString * const NFBNotInterestedTopicsKey = @"nfb_not_interested_topics_tags";
static NSString * const NFBNotificationAdvancedFiltersDidChangeNotification = @"NFBNotificationAdvancedFiltersDidChangeNotification";
static NSString * const NFBNotificationFilterQualityKey = @"nfb_notification_filter_quality";
static NSString * const NFBNotificationFilterYouDoNotFollowKey = @"nfb_notification_filter_you_do_not_follow";
static NSString * const NFBNotificationFilterNotFollowingYouKey = @"nfb_notification_filter_not_following_you";
static NSString * const NFBNotificationFilterNewAccountsKey = @"nfb_notification_filter_new_accounts";
static NSString * const NFBNotificationFilterDefaultAvatarKey = @"nfb_notification_filter_default_avatar";
static NSString * const NFBNotificationEmailEnabledKey = @"nfb_notification_email_enabled";
static NSString * const NFBNotificationEmailActivityKey = @"nfb_notification_email_activity";
static NSString * const NFBNotificationEmailMentionsKey = @"nfb_notification_email_mentions";
static NSString * const NFBNotificationEmailFollowersKey = @"nfb_notification_email_followers";
static NSString * const NFBNotificationEmailMessagesKey = @"nfb_notification_email_messages";
static NSString * const NFBNotificationEmailProductKey = @"nfb_notification_email_product";
static NSString * const NFBSettingsErrorDomain = @"NFBSettings";
static NSString * const NFBChatDeclarationCollection = @"chat.bsky.actor.declaration";
static NSString * const NFBModerationServiceDID = @"did:plc:ar7c4by46qjdydhdevvrndac";
static NSInteger const NFBSettingsRowSubtitleTag = 5101;
static NSInteger const NFBSettingsRowChevronTag = 5102;
static NSInteger const NFBSettingsRowSwitchTag = 5103;
static NSInteger const NFBSettingsRowBorderTag = 5104;

@interface NFBSettingsRowCell : UITableViewCell

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UISwitch *toggleSwitch;
@property (nonatomic, strong) UIImageView *chevronView;
@property (nonatomic, strong) UIImageView *loadingView;
@property (nonatomic, strong) UIView *bottomBorder;

- (void)configureWithItem:(NSDictionary *)item row:(NSInteger)row target:(id)target action:(SEL)action;

@end

@implementation NFBSettingsRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) {
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleDefault);

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = NFBFont(16.0, NFBFontWeightMedium);
    self.titleLabel.numberOfLines = 1;
    self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

    self.subtitleLabel = [[UILabel alloc] init];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.tag = NFBSettingsRowSubtitleTag;
    self.subtitleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
    self.subtitleLabel.numberOfLines = 0;
    self.subtitleLabel.lineBreakMode = NSLineBreakByWordWrapping;

    UIStackView *labels = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.subtitleLabel]];
    labels.translatesAutoresizingMaskIntoConstraints = NO;
    labels.axis = UILayoutConstraintAxisVertical;
    labels.alignment = UIStackViewAlignmentFill;
    labels.spacing = 2.0;

	    self.chevronView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_chevron_right")];
    self.chevronView.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronView.tag = NFBSettingsRowChevronTag;
    self.chevronView.contentMode = UIViewContentModeScaleAspectFit;

    self.toggleSwitch = [[UISwitch alloc] init];
    self.toggleSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.toggleSwitch.tag = NFBSettingsRowSwitchTag;

    self.loadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingView.tintColor = NFBColorSecondaryText();
    self.loadingView.contentMode = UIViewContentModeScaleAspectFit;
    self.loadingView.hidden = YES;

    self.bottomBorder = [[UIView alloc] init];
    self.bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBorder.tag = NFBSettingsRowBorderTag;

    [self.contentView addSubview:labels];
    [self.contentView addSubview:self.chevronView];
    [self.contentView addSubview:self.toggleSwitch];
    [self.contentView addSubview:self.loadingView];
    [self.contentView addSubview:self.bottomBorder];

    [NSLayoutConstraint activateConstraints:@[
      [labels.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
      [labels.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronView.leadingAnchor constant:-14.0],
      [labels.trailingAnchor constraintLessThanOrEqualToAnchor:self.toggleSwitch.leadingAnchor constant:-14.0],
      [labels.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
      [labels.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
      [self.chevronView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
      [self.chevronView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
      [self.chevronView.widthAnchor constraintEqualToConstant:15.0],
      [self.chevronView.heightAnchor constraintEqualToConstant:15.0],
      [self.toggleSwitch.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-20.0],
      [self.toggleSwitch.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
      [self.loadingView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
      [self.loadingView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
      [self.loadingView.widthAnchor constraintEqualToConstant:28.0],
      [self.loadingView.heightAnchor constraintEqualToConstant:28.0],
      [self.bottomBorder.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
      [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
      [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
      [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:60.0]
    ]];
  }
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  [self.toggleSwitch removeTarget:nil action:NULL forControlEvents:UIControlEventValueChanged];
  NFBStopLoadingAnimation(self.loadingView);
  self.loadingView.hidden = YES;
}

- (void)configureWithItem:(NSDictionary *)item row:(NSInteger)row target:(id)target action:(SEL)action {
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"button";
  NSString *subtitle = [item[@"subtitle"] isKindOfClass:NSString.class] ? item[@"subtitle"] : @"";
  NSString *title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : @"";
  BOOL isLoading = [type isEqualToString:@"loading"] || [title isEqualToString:@"Loading..."];
  BOOL isToggle = [type isEqualToString:@"toggle"];
  BOOL selectable = [type isEqualToString:@"button"] || [type isEqualToString:@"select"];
  BOOL enabled = ![item[@"disabled"] boolValue];

  self.titleLabel.text = title;
  self.subtitleLabel.text = subtitle;
  self.subtitleLabel.hidden = subtitle.length == 0;
  self.chevronView.hidden = !selectable || !enabled;
  self.toggleSwitch.hidden = !isToggle;
  self.loadingView.hidden = YES;
  self.selectionStyle = (selectable && enabled) ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;

  if (isLoading) {
    self.titleLabel.hidden = YES;
    self.subtitleLabel.hidden = YES;
    self.chevronView.hidden = YES;
    self.toggleSwitch.hidden = YES;
    self.loadingView.tintColor = NFBColorSecondaryText();
    NFBStartLoadingAnimation(self.loadingView);
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
    NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
    return;
  }
  self.titleLabel.hidden = NO;

  if (isToggle) {
    NSString *key = [item[@"key"] isKindOfClass:NSString.class] ? item[@"key"] : @"";
    BOOL fallback = [item[@"default"] respondsToSelector:@selector(boolValue)] ? [item[@"default"] boolValue] : NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([item[@"value"] respondsToSelector:@selector(boolValue)]) self.toggleSwitch.on = [item[@"value"] boolValue];
    else self.toggleSwitch.on = [defaults objectForKey:key] ? [defaults boolForKey:key] : fallback;
    self.toggleSwitch.enabled = enabled;
    self.toggleSwitch.tag = row;
    [self.toggleSwitch addTarget:target action:action forControlEvents:UIControlEventValueChanged];
  }

  NFBIPAApplyTableCellAppearance(self, self.selectionStyle);
  self.titleLabel.textColor = enabled ? NFBColorText() : NFBColorSecondaryText();
  self.subtitleLabel.textColor = NFBColorSecondaryText();
  self.chevronView.tintColor = NFBColorSecondaryText();
  self.toggleSwitch.onTintColor = NFBColorAccent();
  self.loadingView.tintColor = NFBColorSecondaryText();
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
}

@end

@interface NFBAppIconItem : NSObject

@property (nonatomic, copy, readonly) NSString *bundleIconName;
@property (nonatomic, copy, readonly) NSArray<NSString *> *bundleIconFiles;
@property (nonatomic, assign, readonly, getter=isPrimaryIcon) BOOL primaryIcon;

- (instancetype)initWithBundleIconName:(NSString *)bundleIconName
                         iconFileNames:(NSArray<NSString *> *)iconFileNames
                         isPrimaryIcon:(BOOL)isPrimaryIcon;

@end

@implementation NFBAppIconItem

- (instancetype)initWithBundleIconName:(NSString *)bundleIconName
                         iconFileNames:(NSArray<NSString *> *)iconFileNames
                         isPrimaryIcon:(BOOL)isPrimaryIcon {
  self = [super init];
  if (self) {
    _bundleIconName = [bundleIconName copy] ?: @"Icon";
    _bundleIconFiles = [iconFileNames copy] ?: @[];
    _primaryIcon = isPrimaryIcon;
  }
  return self;
}

@end

@interface NFBAppIconCell : UICollectionViewCell

@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIImageView *checkView;

- (void)configureWithImage:(UIImage *)image selected:(BOOL)selected;

@end

@implementation NFBAppIconCell

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    self.imageView = [[UIImageView alloc] init];
    self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.clipsToBounds = YES;
    self.imageView.layer.cornerRadius = 22.0;
    self.imageView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.imageView.layer.shadowOffset = CGSizeMake(0.0, 4.0);
    self.imageView.layer.shadowOpacity = 0.15;
    self.imageView.layer.shadowRadius = 8.0;

	    self.checkView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_circle")];
    self.checkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkView.contentMode = UIViewContentModeScaleAspectFit;

    [self.contentView addSubview:self.imageView];
    [self.contentView addSubview:self.checkView];

    [NSLayoutConstraint activateConstraints:@[
      [self.imageView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
      [self.imageView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
      [self.imageView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [self.imageView.widthAnchor constraintEqualToConstant:98.0],
      [self.imageView.heightAnchor constraintEqualToConstant:98.0],
      [self.checkView.topAnchor constraintEqualToAnchor:self.imageView.bottomAnchor constant:12.0],
      [self.checkView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
      [self.checkView.widthAnchor constraintEqualToConstant:24.0],
      [self.checkView.heightAnchor constraintEqualToConstant:24.0]
    ]];
  }
  return self;
}

- (void)configureWithImage:(UIImage *)image selected:(BOOL)selected {
  self.imageView.image = image ?: NFBBrandIconImage();
	  self.checkView.image = NFBTemplateIcon(selected ? @"nfb_checkmark_circle" : @"nfb_circle");
  self.checkView.tintColor = selected ? NFBColorAccent() : NFBColorSecondaryText();
}

@end

@interface NFBAppIconSettingsViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, copy) NSArray<NSString *> *sectionTitles;
@property (nonatomic, copy) NSArray<NSArray<NFBAppIconItem *> *> *sectionedIcons;

@end

@implementation NFBAppIconSettingsViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.titleView = NFBTitleView(@"App icon", nil);
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));

  UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
  layout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
  layout.minimumLineSpacing = 10.0;
  layout.minimumInteritemSpacing = 10.0;

  self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
  self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
  self.collectionView.alwaysBounceVertical = YES;
  self.collectionView.showsVerticalScrollIndicator = NO;
  self.collectionView.backgroundColor = NFBColorBackground();
  self.collectionView.dataSource = self;
  self.collectionView.delegate = self;
  [self.collectionView registerClass:NFBAppIconCell.class forCellWithReuseIdentifier:@"appicon"];
  [self.collectionView registerClass:UICollectionReusableView.class
          forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                 withReuseIdentifier:@"HeaderView"];

  self.view.backgroundColor = NFBColorBackground();
  [self.view addSubview:self.collectionView];
  [NSLayoutConstraint activateConstraints:@[
    [self.collectionView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.collectionView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.collectionView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.collectionView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];

  [self setupAppIcons];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.navigationController.interactivePopGestureRecognizer.enabled = self.navigationController.viewControllers.count > 1;
  self.navigationController.interactivePopGestureRecognizer.delegate = nil;
}

- (void)setupAppIcons {
  NSDictionary *iconsDict = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleIcons"];
  NSMutableArray<NFBAppIconItem *> *flat = [NSMutableArray array];

  NSDictionary *primary = [iconsDict[@"CFBundlePrimaryIcon"] isKindOfClass:NSDictionary.class] ? iconsDict[@"CFBundlePrimaryIcon"] : @{};
  [flat addObject:[[NFBAppIconItem alloc] initWithBundleIconName:primary[@"CFBundleIconName"] ?: @"Icon"
                                                   iconFileNames:primary[@"CFBundleIconFiles"] ?: @[@"Icon", @"Icon_rounded"]
                                                   isPrimaryIcon:YES]];

  NSDictionary *alternates = [iconsDict[@"CFBundleAlternateIcons"] isKindOfClass:NSDictionary.class] ? iconsDict[@"CFBundleAlternateIcons"] : @{};
  NSArray<NSString *> *keys = [alternates.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
  for (NSString *key in keys) {
    NSDictionary *alternate = [alternates[key] isKindOfClass:NSDictionary.class] ? alternates[key] : @{};
    [flat addObject:[[NFBAppIconItem alloc] initWithBundleIconName:alternate[@"CFBundleIconName"] ?: key
                                                     iconFileNames:alternate[@"CFBundleIconFiles"] ?: @[]
                                                     isPrimaryIcon:NO]];
  }

  NSArray<NSString *> *categories = @[@"Icons", @"Seasonal", @"Holidays", @"Sports", @"Events", @"Pride", @"Legacy", @"Other"];
  NSMutableDictionary<NSString *, NSMutableArray<NFBAppIconItem *> *> *buckets = [NSMutableDictionary dictionary];
  for (NSString *category in categories) buckets[category] = [NSMutableArray array];

  NSSet<NSString *> *seasonKeys = [NSSet setWithArray:@[@"Autumn", @"Summer", @"Winter", @"Spring", @"Fall"]];
  NSSet<NSString *> *holidayKeys = [NSSet setWithArray:@[@"BlackHistory", @"Holi", @"EarthHour", @"WomansDay", @"LunarNewYear", @"StPatricksDay", @"Christmas", @"NewYears", @"Halloween", @"Thanksgiving", @"ValentinesDay", @"Ramadan", @"Easter", @"Eid", @"Anzac", @"Diwali", @"MayTheFourth", @"MothersDay", @"CanadaDay", @"CanadaIndigenous", @"FathersDay", @"IndependenceDay", @"LaborDay", @"MemorialDay", @"VeteransDay", @"NationalDay", @"FlagDay", @"Juneteenth", @"Euro"]];
  NSSet<NSString *> *sportKeys = [NSSet setWithArray:@[@"BeijingOlympics", @"FormulaOne", @"Daytona", @"Nba", @"Ncaa", @"Masters", @"Nfl", @"Nhl", @"UefaChampionsLeague", @"WorldCup", @"Wimbledon", @"WorldSeries", @"SuperBowl", @"Olympics", @"KentuckyDerby", @"Rugby", @"Cricket", @"Tennis", @"Golf", @"Baseball", @"Football", @"Soccer", @"Basketball", @"Hockey", @"Mlb", @"NBA", @"NHL", @"NFL", @"MLS", @"UFC", @"WWE", @"NBAFinals", @"NHLPlayoffs", @"WorldCup2022", @"Euro2020", @"ChampionsLeagueFinal", @"SuperBowlLV", @"Wimbledon2021", @"FrenchOpen2021", @"USOpen2021", @"StanleyCup"]];
  NSSet<NSString *> *eventKeys = [NSSet setWithArray:@[@"Eurovision"]];
  NSSet<NSString *> *prideKeys = [NSSet setWithArray:@[@"Pride", @"LGBTQ", @"Rainbow", @"Gay"]];

  for (NFBAppIconItem *item in flat) {
    NSString *name = item.bundleIconName ?: @"";
    if (item.isPrimaryIcon || [name isEqualToString:@"ProductionAppIcon"] || [name hasPrefix:@"Custom-Icon"]) {
      [buckets[@"Icons"] addObject:item];
      continue;
    }
    if ([name hasPrefix:@"Legacy-Icon"]) {
      [buckets[@"Legacy"] addObject:item];
      continue;
    }

    BOOL placed = NO;
    NSArray<NSDictionary *> *categoryChecks = @[
      @{@"title": @"Seasonal", @"keys": seasonKeys},
      @{@"title": @"Holidays", @"keys": holidayKeys},
      @{@"title": @"Sports", @"keys": sportKeys},
      @{@"title": @"Events", @"keys": eventKeys},
      @{@"title": @"Pride", @"keys": prideKeys}
    ];
    for (NSDictionary *check in categoryChecks) {
      NSSet<NSString *> *words = check[@"keys"];
      for (NSString *word in words) {
        if ([name containsString:word]) {
          [buckets[check[@"title"]] addObject:item];
          placed = YES;
          break;
        }
      }
      if (placed) break;
    }
    if (!placed) [buckets[@"Other"] addObject:item];
  }

  NSMutableArray<NSString *> *titles = [NSMutableArray array];
  NSMutableArray<NSArray<NFBAppIconItem *> *> *sections = [NSMutableArray array];
  for (NSString *category in categories) {
    NSArray<NFBAppIconItem *> *items = buckets[category];
    if (items.count == 0) continue;
    [titles addObject:category];
    [sections addObject:items];
  }
  self.sectionTitles = titles;
  self.sectionedIcons = sections;
  [self.collectionView reloadData];
}

- (UIImage *)imageForItem:(NFBAppIconItem *)item {
  if (item.isPrimaryIcon) {
    UIImage *primary = NFBBrandIconImage();
    if (primary) return primary;
  }
  UIImage *image = [UIImage imageNamed:item.bundleIconName];
  if (image) return image;
  for (NSString *base in item.bundleIconFiles.reverseObjectEnumerator) {
    image = [UIImage imageNamed:base];
    if (image) return image;
    image = NFBBundledImage(@"NeoFreeBirdMain", base, @"png");
    if (image) return image;
  }
  return NFBBrandIconImage();
}

- (BOOL)itemIsSelected:(NFBAppIconItem *)item {
  NSString *current = UIApplication.sharedApplication.alternateIconName;
  if (current.length > 0) return [current isEqualToString:item.bundleIconName];
  NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:NFBLastSelectedAppIconKey];
  if (saved.length > 0) {
    if ([saved isEqualToString:@"PrimaryIcon"]) return item.isPrimaryIcon;
    return [saved isEqualToString:item.bundleIconName];
  }
  return item.isPrimaryIcon;
}

- (void)backTapped {
  if (self.navigationController.viewControllers.firstObject != self) {
    [self.navigationController popViewControllerAnimated:YES];
  } else if (self.navigationController.presentingViewController) {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  self.collectionView.backgroundColor = NFBColorBackground();
  NFBApplyNavigationAppearance(self.navigationController);
  [self.collectionView reloadData];
}

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
  (void)collectionView;
  return (NSInteger)self.sectionedIcons.count;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
  (void)collectionView;
  return (NSInteger)self.sectionedIcons[(NSUInteger)section].count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
  NFBAppIconCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"appicon" forIndexPath:indexPath];
  NFBAppIconItem *item = self.sectionedIcons[(NSUInteger)indexPath.section][(NSUInteger)indexPath.item];
  [cell configureWithImage:[self imageForItem:item] selected:[self itemIsSelected:item]];
  return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
  UICollectionReusableView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:@"HeaderView" forIndexPath:indexPath];
  for (UIView *subview in header.subviews) [subview removeFromSuperview];
  header.backgroundColor = NFBColorBackground();

  NSString *category = self.sectionTitles[(NSUInteger)indexPath.section];
  if (indexPath.section == 0) {
    UILabel *detail = [[UILabel alloc] init];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.font = NFBFont(13.0, NFBFontWeightRegular);
    detail.textColor = NFBColorSecondaryText();
    detail.numberOfLines = 0;
    detail.text = @"Choose a custom app icon for your device's home screen. Change it any time.";
    [header addSubview:detail];
    [NSLayoutConstraint activateConstraints:@[
      [detail.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
      [detail.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
      [detail.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
      [detail.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-8.0]
    ]];
    return header;
  }

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.font = NFBFont(16.0, NFBFontWeightHeavy);
  title.textColor = NFBColorText();
  title.text = category;
  [header addSubview:title];

  UILabel *detail = [[UILabel alloc] init];
  detail.translatesAutoresizingMaskIntoConstraints = NO;
  detail.font = NFBFont(13.0, NFBFontWeightRegular);
  detail.textColor = NFBColorSecondaryText();
  detail.numberOfLines = 0;
  detail.text = [self detailForIconCategory:category];
  detail.hidden = detail.text.length == 0;
  [header addSubview:detail];

  [NSLayoutConstraint activateConstraints:@[
    [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
    [title.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
    [detail.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
    [detail.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    [detail.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4.0],
    [detail.bottomAnchor constraintLessThanOrEqualToAnchor:header.bottomAnchor constant:-8.0]
  ]];
  return header;
}

- (NSString *)detailForIconCategory:(NSString *)category {
  if ([category isEqualToString:@"Seasonal"]) return @"Icons that change with the season.";
  if ([category isEqualToString:@"Holidays"]) return @"Holiday and observance icons.";
  if ([category isEqualToString:@"Sports"]) return @"Sports event icons.";
  if ([category isEqualToString:@"Events"]) return @"Special event icons.";
  if ([category isEqualToString:@"Pride"]) return @"Pride icons.";
  if ([category isEqualToString:@"Legacy"]) return @"Classic Twitter app icons.";
  return @"";
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  NFBAppIconItem *item = self.sectionedIcons[(NSUInteger)indexPath.section][(NSUInteger)indexPath.item];
  NSString *identifier = item.isPrimaryIcon ? @"PrimaryIcon" : item.bundleIconName;
  [NSUserDefaults.standardUserDefaults setObject:identifier forKey:NFBLastSelectedAppIconKey];
  [NSUserDefaults.standardUserDefaults synchronize];

  if (![UIApplication.sharedApplication supportsAlternateIcons]) {
    [collectionView reloadData];
    return;
  }

  NSString *iconName = item.isPrimaryIcon ? nil : item.bundleIconName;
  __weak typeof(self) weakSelf = self;
  [UIApplication.sharedApplication setAlternateIconName:iconName completionHandler:^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      if (error) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't change icon"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
        [strongSelf presentViewController:alert animated:YES completion:nil];
      }
      [strongSelf.collectionView reloadData];
    });
  }];
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)layout
referenceSizeForHeaderInSection:(NSInteger)section {
  (void)layout;
  if (section == 0) return CGSizeMake(CGRectGetWidth(collectionView.bounds), 60.0);
  NSString *category = self.sectionTitles[(NSUInteger)section];
  BOOL hasDetail = ![[self detailForIconCategory:category] isEqualToString:@""];
  return CGSizeMake(CGRectGetWidth(collectionView.bounds), hasDetail ? 60.0 : 30.0);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
  (void)collectionView;
  (void)layout;
  (void)indexPath;
  return CGSizeMake(98.0, 136.0);
}

@end

@interface NFBTopicCategoryViewController : UIViewController

@property (nonatomic, assign) CGFloat topicLayoutWidth;
@property (nonatomic, copy) NSString *categoryTitle;
@property (nonatomic, copy) NSArray<NSString *> *topics;
@property (nonatomic, copy) BOOL (^selectedBlock)(NSString *tag);
@property (nonatomic, copy) void (^toggleBlock)(NSString *tag);
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;

- (instancetype)initWithTitle:(NSString *)title
                       topics:(NSArray<NSString *> *)topics
                selectedBlock:(BOOL (^)(NSString *tag))selectedBlock
                  toggleBlock:(void (^)(NSString *tag))toggleBlock;

@end

@implementation NFBTopicCategoryViewController

- (instancetype)initWithTitle:(NSString *)title
                       topics:(NSArray<NSString *> *)topics
                selectedBlock:(BOOL (^)(NSString *tag))selectedBlock
                  toggleBlock:(void (^)(NSString *tag))toggleBlock {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _categoryTitle = [title copy] ?: @"Topics";
    _topics = [topics copy] ?: @[];
    _selectedBlock = [selectedBlock copy];
    _toggleBlock = [toggleBlock copy];
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.titleView = NFBTitleView(self.categoryTitle, nil);
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  self.view.backgroundColor = NFBColorBackground();

  self.scrollView = [[UIScrollView alloc] init];
  self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.scrollView.alwaysBounceVertical = YES;
  self.scrollView.showsVerticalScrollIndicator = NO;
  self.scrollView.backgroundColor = NFBColorBackground();

  self.contentStack = [[UIStackView alloc] init];
  self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentStack.axis = UILayoutConstraintAxisVertical;
  self.contentStack.alignment = UIStackViewAlignmentFill;
  self.contentStack.spacing = 10.0;

  [self.view addSubview:self.scrollView];
  [self.scrollView addSubview:self.contentStack];
  [NSLayoutConstraint activateConstraints:@[
    [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:16.0],
    [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor constant:16.0],
    [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor constant:-16.0],
    [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-34.0],
    [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor constant:-32.0]
  ]];
  [self rebuildTopics];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.navigationController.interactivePopGestureRecognizer.enabled = self.navigationController.viewControllers.count > 1;
  self.navigationController.interactivePopGestureRecognizer.delegate = nil;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width > 0 && fabs(width - self.topicLayoutWidth) > .5) {
    self.topicLayoutWidth = width;
    [self rebuildTopics];
  }
}

- (void)rebuildTopics {
  for (UIView *view in self.contentStack.arrangedSubviews) {
    [self.contentStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  for (UIStackView *row in [self wrappedRowsForTopics:self.topics ?: @[]]) {
    [self.contentStack addArrangedSubview:row];
  }
}

- (NSArray<UIStackView *> *)wrappedRowsForTopics:(NSArray<NSString *> *)topics {
  NSMutableArray *rows = [NSMutableArray array];
  CGFloat maxWidth = CGRectGetWidth(self.view.bounds) - 32.0;
  if (maxWidth < 260.0) maxWidth = UIScreen.mainScreen.bounds.size.width - 32.0;
  UIFont *font = NFBFont(15.0, NFBFontWeightBold);
  CGFloat spacing = 10.0;
  CGFloat currentWidth = 0.0;
  UIStackView *row = nil;
  for (NSString *topic in topics) {
    // Measure the complete title, including the widest selection mark and theme insets.
    NSString *fullTitle = [topic stringByAppendingString:@"  ✓"];
    CGFloat textWidth = [fullTitle boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 24.0)
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:@{NSFontAttributeName: font}
                                           context:nil].size.width;
    CGFloat chipWidth = MIN(maxWidth, MAX(82.0, ceil(textWidth + 36.0)));
    if (!row || (currentWidth + chipWidth + spacing > maxWidth && row.arrangedSubviews.count > 0)) {
      row = [[UIStackView alloc] init];
      row.translatesAutoresizingMaskIntoConstraints = NO;
      row.axis = UILayoutConstraintAxisHorizontal;
      row.alignment = UIStackViewAlignmentLeading;
      row.distribution = UIStackViewDistributionFill;
      row.spacing = spacing;
      [rows addObject:row];
      currentWidth = 0.0;
    }
    UIButton *chip = [self chipButtonForTopic:topic width:chipWidth];
    [row addArrangedSubview:chip];
    currentWidth += chipWidth + spacing;
  }
  for (UIStackView *completedRow in rows) {
    UIView *flexibleSpace = [UIView new];
    [flexibleSpace setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [completedRow addArrangedSubview:flexibleSpace];
  }
  return rows;
}

- (UIButton *)chipButtonForTopic:(NSString *)topic width:(CGFloat)width {
  NSString *tag = [self normalizedTopicTag:topic];
  BOOL selected = self.selectedBlock ? self.selectedBlock(tag) : NO;
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.accessibilityIdentifier = tag;
  NFBIPAApplyButtonAppearance(button, selected ? NFBIPAButtonStylePrimary : NFBIPAButtonStyleNeutralOutline, NFBIPAButtonSizeMedium);
  button.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 16.0, 8.0, 16.0);
  button.titleLabel.numberOfLines = 0;
  button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
  button.titleLabel.textAlignment = NSTextAlignmentCenter;
  button.titleLabel.adjustsFontSizeToFitWidth = NO;
  NSString *mark = selected ? @"✓" : @"+";
  [button setTitle:[NSString stringWithFormat:@"%@  %@", topic, mark] forState:UIControlStateNormal];
  [button addTarget:self action:@selector(topicChipTapped:) forControlEvents:UIControlEventTouchUpInside];
  [NSLayoutConstraint activateConstraints:@[
    [button.widthAnchor constraintEqualToConstant:width],
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:36.0],
    [button.heightAnchor constraintEqualToConstant:MAX(36.0, ceil([button.currentTitle boundingRectWithSize:CGSizeMake(MAX(1, width - 32), CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:button.titleLabel.font} context:nil].size.height) + 16.0)]
  ]];
  return button;
}

- (NSString *)normalizedTopicTag:(NSString *)topic {
  NSString *safe = [[topic stringByReplacingOccurrencesOfString:@"#" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return safe.lowercaseString ?: @"";
}

- (void)topicChipTapped:(UIButton *)sender {
  NSString *tag = sender.accessibilityIdentifier ?: @"";
  if (tag.length == 0) return;
  if (self.toggleBlock) self.toggleBlock(tag);
  [self rebuildTopics];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  self.scrollView.backgroundColor = NFBColorBackground();
  NFBApplyNavigationAppearance(self.navigationController);
  [self rebuildTopics];
}

@end

@interface NFBTopicsSettingsViewController : UIViewController

@property (nonatomic, assign) CGFloat topicLayoutWidth;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, copy) NSArray<UIButton *> *tabButtons;
@property (nonatomic, copy) NSArray<UIView *> *tabIndicators;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *preferences;
@property (nonatomic, strong) NSMutableSet<NSString *> *selectedTags;
@property (nonatomic, strong) NSMutableSet<NSString *> *notInterestedTags;
@property (nonatomic, assign) NSInteger selectedTabIndex;
@property (nonatomic, assign) BOOL loading;

@end

@implementation NFBTopicsSettingsViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.titleView = NFBTitleView(@"Topics", nil);
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));

  UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeCustom];
  infoButton.frame = CGRectMake(0.0, 0.0, 34.0, 34.0);
  [infoButton setImage:NFBTemplateIcon(@"nfb_info") forState:UIControlStateNormal];
  infoButton.tintColor = NFBColorSecondaryText();
  [infoButton addTarget:self action:@selector(infoTapped) forControlEvents:UIControlEventTouchUpInside];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:infoButton];

  self.preferences = [NSMutableArray array];
  self.selectedTags = [NSMutableSet set];
  NSArray *notInterested = [NSUserDefaults.standardUserDefaults arrayForKey:NFBNotInterestedTopicsKey];
  self.notInterestedTags = [NSMutableSet setWithArray:notInterested ?: @[]];
  self.selectedTabIndex = 0;
  [self buildContent];
  [self fetchPreferences];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.navigationController.interactivePopGestureRecognizer.enabled = self.navigationController.viewControllers.count > 1;
  self.navigationController.interactivePopGestureRecognizer.delegate = nil;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildContent {
  self.view.backgroundColor = NFBColorBackground();

  UIView *tabBar = [self topicsTabBar];
  self.scrollView = [[UIScrollView alloc] init];
  self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
  self.scrollView.alwaysBounceVertical = YES;
  self.scrollView.showsVerticalScrollIndicator = NO;
  self.scrollView.backgroundColor = NFBColorBackground();

  self.contentStack = [[UIStackView alloc] init];
  self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.contentStack.axis = UILayoutConstraintAxisVertical;
  self.contentStack.alignment = UIStackViewAlignmentFill;
  self.contentStack.spacing = 0.0;

  [self.view addSubview:tabBar];
  [self.view addSubview:self.scrollView];
  [self.scrollView addSubview:self.contentStack];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [tabBar.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [tabBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [tabBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [tabBar.heightAnchor constraintEqualToConstant:50.0],
    [self.scrollView.topAnchor constraintEqualToAnchor:tabBar.bottomAnchor],
    [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
    [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
    [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
    [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
    [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]
  ]];
  [self rebuildTopics];
}

- (UIView *)topicsTabBar {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.backgroundColor = NFBColorBackground();

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.distribution = UIStackViewDistributionFillEqually;
  stack.spacing = 0.0;

  NSMutableArray *buttons = [NSMutableArray array];
  NSMutableArray *indicators = [NSMutableArray array];
  NSArray *titles = @[@"Suggested", @"Following", @"Not Interested"];
  for (NSUInteger i = 0; i < titles.count; i++) {
    UIView *item = [[UIView alloc] init];
    item.translatesAutoresizingMaskIntoConstraints = NO;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = (NSInteger)i;
    button.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
    [button setTitle:titles[i] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIView *indicator = [[UIView alloc] init];
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    indicator.layer.cornerRadius = 2.0;

    [item addSubview:button];
    [item addSubview:indicator];
    [NSLayoutConstraint activateConstraints:@[
      [button.topAnchor constraintEqualToAnchor:item.topAnchor],
      [button.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
      [button.trailingAnchor constraintEqualToAnchor:item.trailingAnchor],
      [button.bottomAnchor constraintEqualToAnchor:item.bottomAnchor],
      [indicator.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:14.0],
      [indicator.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-14.0],
      [indicator.bottomAnchor constraintEqualToAnchor:item.bottomAnchor],
      [indicator.heightAnchor constraintEqualToConstant:4.0]
    ]];
    [stack addArrangedSubview:item];
    [buttons addObject:button];
    [indicators addObject:indicator];
  }

  UIView *border = [[UIView alloc] init];
  border.translatesAutoresizingMaskIntoConstraints = NO;
  border.backgroundColor = NFBColorBorder();

  [container addSubview:stack];
  [container addSubview:border];
  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:container.topAnchor],
    [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    [border.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [border.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [border.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    [border.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];

  self.tabButtons = buttons;
  self.tabIndicators = indicators;
  [self updateTabs];
  return container;
}

- (void)fetchPreferences {
  self.loading = YES;
  [self rebuildTopics];
  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    self.loading = NO;
    [self rebuildTopics];
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcGET:@"app.bsky.actor.getPreferences"
                                     service:nil
                                      params:nil
                               authenticated:YES
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.loading = NO;
      if (!error && [value isKindOfClass:NSDictionary.class] && [value[@"preferences"] isKindOfClass:NSArray.class]) {
        NSMutableArray *preferences = [NSMutableArray array];
        [self.selectedTags removeAllObjects];
        for (NSDictionary *preference in value[@"preferences"]) {
          if (![preference isKindOfClass:NSDictionary.class]) continue;
          [preferences addObject:[preference mutableCopy]];
          if ([preference[@"$type"] isEqualToString:@"app.bsky.actor.defs#interestsPref"] && [preference[@"tags"] isKindOfClass:NSArray.class]) {
            for (NSString *tag in preference[@"tags"]) {
              if ([tag isKindOfClass:NSString.class] && tag.length > 0) [self.selectedTags addObject:[self normalizedTopicTag:tag]];
            }
          }
        }
        self.preferences = preferences;
      }
      [self rebuildTopics];
    });
  }];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  if (width > 0 && fabs(width - self.topicLayoutWidth) > .5) {
    self.topicLayoutWidth = width;
    [self rebuildTopics];
  }
}

- (void)rebuildTopics {
  for (UIView *view in self.contentStack.arrangedSubviews) {
    [self.contentStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  self.view.backgroundColor = NFBColorBackground();
  self.scrollView.backgroundColor = NFBColorBackground();
  [self updateTabs];

  if (self.loading) {
    UIView *loadingContainer = [[UIView alloc] init];
    loadingContainer.translatesAutoresizingMaskIntoConstraints = NO;
    UIImageView *loadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    loadingView.tintColor = NFBColorSecondaryText();
    loadingView.contentMode = UIViewContentModeScaleAspectFit;
    [loadingContainer addSubview:loadingView];
    [NSLayoutConstraint activateConstraints:@[
      [loadingContainer.heightAnchor constraintEqualToConstant:160.0],
      [loadingView.centerXAnchor constraintEqualToAnchor:loadingContainer.centerXAnchor],
      [loadingView.centerYAnchor constraintEqualToAnchor:loadingContainer.centerYAnchor],
      [loadingView.widthAnchor constraintEqualToConstant:30.0],
      [loadingView.heightAnchor constraintEqualToConstant:30.0]
    ]];
    NFBStartLoadingAnimation(loadingView);
    [self.contentStack addArrangedSubview:loadingContainer];
    return;
  }

  NSArray<NSDictionary *> *sections = [self visibleTopicSections];
  if (sections.count == 0) {
    [self.contentStack addArrangedSubview:[self emptyTopicsView]];
    return;
  }
  for (NSDictionary *section in sections) {
    [self.contentStack addArrangedSubview:[self topicSectionViewWithTitle:section[@"title"] topics:section[@"topics"]]];
  }
  UIView *spacer = [[UIView alloc] init];
  spacer.translatesAutoresizingMaskIntoConstraints = NO;
  [spacer.heightAnchor constraintEqualToConstant:34.0].active = YES;
  [self.contentStack addArrangedSubview:spacer];
}

- (UIView *)topicSectionViewWithTitle:(NSString *)title topics:(NSArray<NSString *> *)topics {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.backgroundColor = NFBColorBackground();

  UIStackView *stack = [[UIStackView alloc] init];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisVertical;
  stack.alignment = UIStackViewAlignmentFill;
  stack.spacing = 10.0;

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.font = NFBFont(17.0, NFBFontWeightHeavy);
  titleLabel.textColor = NFBColorText();
  titleLabel.text = title ?: @"";
  [stack addArrangedSubview:titleLabel];

  NSArray *allTopics = topics ?: @[];
  NSArray *previewTopics = allTopics;
  if (self.selectedTabIndex == 0 && allTopics.count > 5) {
    previewTopics = [allTopics subarrayWithRange:NSMakeRange(0, 5)];
  }

  for (UIStackView *row in [self wrappedRowsForTopics:previewTopics]) {
    [stack addArrangedSubview:row];
  }

  if (self.selectedTabIndex == 0 && allTopics.count > previewTopics.count) {
    UIButton *viewAll = [NFBPillButton buttonWithType:UIButtonTypeCustom];
    viewAll.translatesAutoresizingMaskIntoConstraints = NO;
    viewAll.accessibilityIdentifier = title ?: @"";
    viewAll.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    NFBIPAApplyButtonAppearance(viewAll, NFBIPAButtonStyleText, NFBIPAButtonSizeCompact);
    viewAll.titleLabel.font = NFBFont(14.0, NFBFontWeightMedium);
    [viewAll setTitle:@"View All" forState:UIControlStateNormal];
    [viewAll addTarget:self action:@selector(viewAllTopicsTapped:) forControlEvents:UIControlEventTouchUpInside];
    [viewAll.heightAnchor constraintEqualToConstant:30.0].active = YES;
    [stack addArrangedSubview:viewAll];
  }

  UIView *border = [[UIView alloc] init];
  border.translatesAutoresizingMaskIntoConstraints = NO;
  border.backgroundColor = NFBColorBorder();

  [container addSubview:stack];
  [container addSubview:border];
  [NSLayoutConstraint activateConstraints:@[
    [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:16.0],
    [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
    [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
    [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-16.0],
    [border.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [border.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [border.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    [border.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  return container;
}

- (NSArray<UIStackView *> *)wrappedRowsForTopics:(NSArray<NSString *> *)topics {
  NSMutableArray *rows = [NSMutableArray array];
  CGFloat maxWidth = CGRectGetWidth(self.view.bounds) - 32.0;
  if (maxWidth < 260.0) maxWidth = UIScreen.mainScreen.bounds.size.width - 32.0;
  UIFont *font = NFBFont(15.0, NFBFontWeightBold);
  CGFloat spacing = 10.0;
  CGFloat currentWidth = 0.0;
  UIStackView *row = nil;
  for (NSString *topic in topics) {
    // Measure the complete title, including the widest selection mark and theme insets.
    NSString *fullTitle = [topic stringByAppendingString:@"  ✓"];
    CGFloat textWidth = [fullTitle boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, 24.0)
                                           options:NSStringDrawingUsesLineFragmentOrigin
                                        attributes:@{NSFontAttributeName: font}
                                           context:nil].size.width;
    CGFloat chipWidth = MIN(maxWidth, MAX(82.0, ceil(textWidth + 36.0)));
    if (!row || (currentWidth + chipWidth + spacing > maxWidth && row.arrangedSubviews.count > 0)) {
      row = [[UIStackView alloc] init];
      row.translatesAutoresizingMaskIntoConstraints = NO;
      row.axis = UILayoutConstraintAxisHorizontal;
      row.alignment = UIStackViewAlignmentLeading;
      row.distribution = UIStackViewDistributionFill;
      row.spacing = spacing;
      [rows addObject:row];
      currentWidth = 0.0;
    }
    UIButton *chip = [self chipButtonForTopic:topic width:chipWidth];
    [row addArrangedSubview:chip];
    currentWidth += chipWidth + spacing;
  }
  for (UIStackView *completedRow in rows) {
    UIView *flexibleSpace = [UIView new];
    [flexibleSpace setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [completedRow addArrangedSubview:flexibleSpace];
  }
  return rows;
}

- (UIButton *)chipButtonForTopic:(NSString *)topic width:(CGFloat)width {
  NSString *tag = [self normalizedTopicTag:topic];
  BOOL selected = self.selectedTabIndex == 2 ? [self.notInterestedTags containsObject:tag] : [self.selectedTags containsObject:tag];
  UIButton *button = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.accessibilityIdentifier = tag;
  NFBIPAApplyButtonAppearance(button, selected ? NFBIPAButtonStylePrimary : NFBIPAButtonStyleNeutralOutline, NFBIPAButtonSizeMedium);
  button.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  button.contentEdgeInsets = UIEdgeInsetsMake(8.0, 16.0, 8.0, 16.0);
  button.titleLabel.numberOfLines = 0;
  button.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
  button.titleLabel.textAlignment = NSTextAlignmentCenter;
  button.titleLabel.adjustsFontSizeToFitWidth = NO;
  NSString *mark = selected ? @"✓" : @"+";
  [button setTitle:[NSString stringWithFormat:@"%@  %@", topic, mark] forState:UIControlStateNormal];
  [button addTarget:self action:@selector(topicChipTapped:) forControlEvents:UIControlEventTouchUpInside];
  [NSLayoutConstraint activateConstraints:@[
    [button.widthAnchor constraintEqualToConstant:width],
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:36.0],
    [button.heightAnchor constraintEqualToConstant:MAX(36.0, ceil([button.currentTitle boundingRectWithSize:CGSizeMake(MAX(1, width - 32), CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:button.titleLabel.font} context:nil].size.height) + 16.0)]
  ]];
  return button;
}

- (UIView *)emptyTopicsView {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.textAlignment = NSTextAlignmentCenter;
  label.numberOfLines = 0;
  label.font = NFBFont(15.0, NFBFontWeightRegular);
  label.textColor = NFBColorSecondaryText();
  if (self.selectedTabIndex == 1) label.text = @"Topics you follow will appear here.";
  else if (self.selectedTabIndex == 2) label.text = @"Topics you mark not interested will appear here.";
  else label.text = @"Sign in with Bluesky to manage Topics.";
  [container addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintEqualToConstant:170.0],
    [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:34.0],
    [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-34.0],
    [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor]
  ]];
  return container;
}

- (NSArray<NSDictionary *> *)visibleTopicSections {
  if (![[NFBAtprotoSession sharedSession] hasSession] && self.selectedTabIndex != 2) return @[];
  NSArray *sections = [self topicSections];
  if (self.selectedTabIndex == 0) return sections;

  NSSet *target = self.selectedTabIndex == 1 ? self.selectedTags : self.notInterestedTags;
  NSMutableArray *filtered = [NSMutableArray array];
  NSMutableSet *seen = [NSMutableSet set];
  for (NSDictionary *section in sections) {
    NSMutableArray *topics = [NSMutableArray array];
    for (NSString *topic in section[@"topics"]) {
      NSString *tag = [self normalizedTopicTag:topic];
      if ([target containsObject:tag]) {
        [topics addObject:topic];
        [seen addObject:tag];
      }
    }
    if (topics.count > 0) [filtered addObject:@{@"title": section[@"title"], @"topics": topics}];
  }
  NSMutableArray *custom = [NSMutableArray array];
  for (NSString *tag in target) {
    if (![seen containsObject:tag]) [custom addObject:[self displayTitleForTag:tag]];
  }
  if (custom.count > 0) {
    NSArray *sorted = [custom sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    [filtered addObject:@{@"title": @"Custom Interests", @"topics": sorted}];
  }
  return filtered;
}

- (NSArray<NSDictionary *> *)topicSections {
  return @[
    @{@"title": @"Arts & Culture", @"topics": @[@"Books", @"Famous quotes", @"Paintings", @"Health & wellness books", @"Photography", @"Drawing & illustration", @"Graphic design"]},
    @{@"title": @"Food", @"topics": @[@"Cooking", @"Organic foods", @"BBQ", @"Food inspiration", @"Baking", @"Recipes", @"Pie", @"Chefs"]},
    @{@"title": @"Fashion & Beauty", @"topics": @[@"Skin care", @"Beauty", @"Tattoos", @"Fashion", @"Makeup", @"Hair"]},
    @{@"title": @"Technology", @"topics": @[@"Apple", @"Software development", @"Web development", @"Linux", @"Gaming", @"AI"]},
    @{@"title": @"Science", @"topics": @[@"Space", @"Climate", @"Biology", @"Physics", @"Medicine"]},
    @{@"title": @"Sports", @"topics": @[@"Baseball", @"Basketball", @"Football", @"Soccer", @"Hockey", @"Motorsports"]}
  ];
}

- (NSString *)normalizedTopicTag:(NSString *)topic {
  NSString *safe = [[topic stringByReplacingOccurrencesOfString:@"#" withString:@""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  return safe.lowercaseString ?: @"";
}

- (NSString *)displayTitleForTag:(NSString *)tag {
  NSArray *parts = [tag componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_ "]];
  NSMutableArray *words = [NSMutableArray array];
  for (NSString *part in parts) {
    if (part.length == 0) continue;
    NSString *first = [[part substringToIndex:1] uppercaseString];
    NSString *rest = part.length > 1 ? [part substringFromIndex:1] : @"";
    [words addObject:[first stringByAppendingString:rest]];
  }
  return words.count > 0 ? [words componentsJoinedByString:@" "] : tag;
}

- (void)tabTapped:(UIButton *)sender {
  self.selectedTabIndex = sender.tag;
  [self rebuildTopics];
}

- (void)topicChipTapped:(UIButton *)sender {
  NSString *tag = sender.accessibilityIdentifier ?: @"";
  [self toggleTopicWithTag:tag];
}

- (void)toggleTopicWithTag:(NSString *)tag {
  if (tag.length == 0) return;
  if (self.selectedTabIndex == 2) {
    if ([self.notInterestedTags containsObject:tag]) [self.notInterestedTags removeObject:tag];
    else [self.notInterestedTags addObject:tag];
    [NSUserDefaults.standardUserDefaults setObject:self.notInterestedTags.allObjects forKey:NFBNotInterestedTopicsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [self rebuildTopics];
    return;
  }

  if ([self.selectedTags containsObject:tag]) [self.selectedTags removeObject:tag];
  else [self.selectedTags addObject:tag];
  [self saveInterests];
  [self rebuildTopics];
}

- (BOOL)topicTagIsSelected:(NSString *)tag {
  NSString *safeTag = tag ?: @"";
  if (self.selectedTabIndex == 2) return [self.notInterestedTags containsObject:safeTag];
  return [self.selectedTags containsObject:safeTag];
}

- (void)viewAllTopicsTapped:(UIButton *)sender {
  NSString *title = sender.accessibilityIdentifier ?: @"";
  NSDictionary *targetSection = nil;
  for (NSDictionary *section in [self visibleTopicSections]) {
    NSString *sectionTitle = [section[@"title"] isKindOfClass:NSString.class] ? section[@"title"] : @"";
    if ([sectionTitle isEqualToString:title]) {
      targetSection = section;
      break;
    }
  }
  if (targetSection.count == 0) return;

  NSArray *topics = [targetSection[@"topics"] isKindOfClass:NSArray.class] ? targetSection[@"topics"] : @[];
  __weak typeof(self) weakSelf = self;
  NFBTopicCategoryViewController *category = [[NFBTopicCategoryViewController alloc] initWithTitle:title.length > 0 ? title : @"Topics"
                                                                                           topics:topics
                                                                                    selectedBlock:^BOOL(NSString *tag) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    return strongSelf ? [strongSelf topicTagIsSelected:tag] : NO;
  }
                                                                                      toggleBlock:^(NSString *tag) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    [strongSelf toggleTopicWithTag:tag];
  }];
  [self.navigationController pushViewController:category animated:YES];
}

- (void)saveInterests {
  NSMutableArray *tags = [NSMutableArray arrayWithArray:self.selectedTags.allObjects];
  [tags sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  NSMutableDictionary *next = [@{@"$type": @"app.bsky.actor.defs#interestsPref", @"tags": tags} mutableCopy];
  NSUInteger index = NSNotFound;
  for (NSUInteger i = 0; i < self.preferences.count; i++) {
    if ([self.preferences[i][@"$type"] isEqualToString:@"app.bsky.actor.defs#interestsPref"]) {
      index = i;
      break;
    }
  }
  if (index == NSNotFound) [self.preferences addObject:next];
  else self.preferences[index] = next;

  [[NFBAtprotoSession sharedSession] xrpcPOST:@"app.bsky.actor.putPreferences"
                                      service:nil
                                         body:@{@"preferences": self.preferences ?: @[]}
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)value;
    (void)response;
    if (!error) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self showError:error.localizedDescription];
    });
  }];
}

- (void)updateTabs {
  for (NSUInteger i = 0; i < self.tabButtons.count; i++) {
    BOOL selected = (NSInteger)i == self.selectedTabIndex;
    UIButton *button = self.tabButtons[i];
    [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
    UIView *indicator = self.tabIndicators[i];
    indicator.hidden = !selected;
    indicator.backgroundColor = NFBColorAccent();
  }
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (void)infoTapped {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Topics"
                                                                 message:@"Bluesky stores followed Topics as private Interests tags. Not Interested Topics are stored locally in Not Twitter."
                                                          preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)showError:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message ?: @"" preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.navigationItem.rightBarButtonItem.customView.tintColor = NFBColorSecondaryText();
  NFBApplyNavigationAppearance(self.navigationController);
  [self rebuildTopics];
}

@end

@interface NFBSettingsDetailViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *sectionID;
@property (nonatomic, copy) NSString *sectionTitle;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *rows;
@property (nonatomic, strong) NSDictionary *account;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *preferences;
@property (nonatomic, strong) NSDictionary *notificationPreferences;
@property (nonatomic, copy) NSString *chatAllowIncoming;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, copy) NSString *errorMessage;

- (instancetype)initWithSectionID:(NSString *)sectionID title:(NSString *)title;

@end

@implementation NFBSettingsDetailViewController

- (instancetype)initWithSectionID:(NSString *)sectionID title:(NSString *)title {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _sectionID = [sectionID copy] ?: @"display";
    _sectionTitle = [title copy] ?: @"Settings";
    _rows = @[];
    _preferences = [NSMutableArray array];
    _notificationPreferences = @{};
    _chatAllowIncoming = @"all";
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.titleView = NFBTitleView(self.sectionTitle, nil);
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  [self buildTable];
  [self reloadSectionData];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.navigationController.interactivePopGestureRecognizer.enabled = self.navigationController.viewControllers.count > 1;
  self.navigationController.interactivePopGestureRecognizer.delegate = nil;
}

- (void)buildTable {
  self.view.backgroundColor = NFBColorBackground();
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.showsVerticalScrollIndicator = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 62.0;
  [self.tableView registerClass:NFBSettingsRowCell.class forCellReuseIdentifier:@"settings"];
  [self.view addSubview:self.tableView];
  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  NFBIPAApplyTableViewAppearance(self.tableView);
  NFBApplyNavigationAppearance(self.navigationController);
  [self.tableView reloadData];
}

- (void)backTapped {
  if (self.navigationController.viewControllers.firstObject != self) {
    [self.navigationController popViewControllerAnimated:YES];
  } else if (self.navigationController.presentingViewController) {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)reloadSectionData {
  self.loading = YES;
  self.errorMessage = nil;
  [self rebuildRows];

  if ([self.sectionID isEqualToString:@"display"] ||
      [self.sectionID isEqualToString:@"blue"] ||
      [self.sectionID isEqualToString:@"undo_tweet"] ||
      [self.sectionID isEqualToString:@"notification_filters"] ||
      [self.sectionID isEqualToString:@"notification_email"]) {
    self.loading = NO;
    [self rebuildRows];
    return;
  }

  if (![[NFBAtprotoSession sharedSession] hasSession]) {
    self.loading = NO;
    self.errorMessage = @"Sign in with Bluesky to manage these settings.";
    [self rebuildRows];
    return;
  }

  if ([self.sectionID isEqualToString:@"account"] || [self.sectionID isEqualToString:@"security"]) {
    [self fetchAccountWithCompletion:^(NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.loading = NO;
        self.errorMessage = error.localizedDescription;
        [self rebuildRows];
      });
    }];
    return;
  }

  if ([self.sectionID isEqualToString:@"notifications"] ||
      [self.sectionID isEqualToString:@"notification_push"]) {
    [self fetchNotificationPreferencesWithCompletion:^(NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.loading = NO;
        self.errorMessage = error.localizedDescription;
        [self rebuildRows];
      });
    }];
    return;
  }

  __weak typeof(self) weakSelf = self;
  [self fetchPreferencesWithCompletion:^(NSError *preferencesError) {
    __strong typeof(weakSelf) strongSelf = weakSelf;
    if (!strongSelf) return;
    if ([strongSelf.sectionID isEqualToString:@"privacy"]) {
      [strongSelf fetchChatSettingsWithCompletion:^(NSError *chatError) {
        dispatch_async(dispatch_get_main_queue(), ^{
          strongSelf.loading = NO;
          strongSelf.errorMessage = preferencesError.localizedDescription ?: chatError.localizedDescription;
          [strongSelf rebuildRows];
        });
      }];
      return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      strongSelf.loading = NO;
      strongSelf.errorMessage = preferencesError.localizedDescription;
      [strongSelf rebuildRows];
    });
  }];
}

- (void)fetchAccountWithCompletion:(void (^)(NSError *error))completion {
  [[NFBAtprotoSession sharedSession] xrpcGET:@"com.atproto.server.getSession"
                                     service:nil
                                      params:nil
                               authenticated:YES
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (!error && [value isKindOfClass:NSDictionary.class]) self.account = value;
    if (completion) completion(error);
  }];
}

- (void)fetchPreferencesWithCompletion:(void (^)(NSError *error))completion {
  [[NFBAtprotoSession sharedSession] xrpcGET:@"app.bsky.actor.getPreferences"
                                     service:nil
                                      params:nil
                               authenticated:YES
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    NSMutableArray *fetchedPreferences = nil;
    if (!error && [value isKindOfClass:NSDictionary.class] && [value[@"preferences"] isKindOfClass:NSArray.class]) {
      fetchedPreferences = [NSMutableArray array];
      for (NSDictionary *preference in value[@"preferences"]) {
        if ([preference isKindOfClass:NSDictionary.class]) [fetchedPreferences addObject:[preference mutableCopy]];
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      if (fetchedPreferences) {
        self.preferences = fetchedPreferences;
        NFBModerationCachePreferences(fetchedPreferences);
      }
      if (completion) completion(error);
    });
  }];
}

- (void)putPreferencesWithCompletion:(void (^)(NSError *error))completion {
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"app.bsky.actor.putPreferences"
                                      service:nil
                                         body:@{@"preferences": self.preferences ?: @[]}
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)value;
    (void)response;
    if (completion) completion(error);
  }];
}

- (void)fetchChatSettingsWithCompletion:(void (^)(NSError *error))completion {
  NSString *did = [NFBAtprotoSession sharedSession].did ?: @"";
  if (did.length == 0) {
    if (completion) completion(nil);
    return;
  }
  [[NFBAtprotoSession sharedSession] xrpcGET:@"com.atproto.repo.getRecord"
                                     service:nil
                                      params:@{@"repo": did, @"collection": NFBChatDeclarationCollection, @"rkey": @"self"}
                               authenticated:YES
                                  completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (!error && [value isKindOfClass:NSDictionary.class]) {
      NSDictionary *record = [value[@"value"] isKindOfClass:NSDictionary.class] ? value[@"value"] : @{};
      NSString *allow = [record[@"allowIncoming"] isKindOfClass:NSString.class] ? record[@"allowIncoming"] : @"all";
      self.chatAllowIncoming = [self normalizedChatAllowIncoming:allow];
    }
    if (completion) completion(nil);
  }];
}

- (void)fetchNotificationPreferencesWithCompletion:(void (^)(NSError *error))completion {
  [[NFBAtprotoSession sharedSession] xrpcGETViaAppViewProxy:@"app.bsky.notification.getPreferences"
                                                     params:nil
                                                 completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)response;
    if (!error && [value isKindOfClass:NSDictionary.class] && [value[@"preferences"] isKindOfClass:NSDictionary.class]) {
      self.notificationPreferences = value[@"preferences"];
    }
    if (completion) completion(error);
  }];
}

- (void)rebuildRows {
  NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
  if (self.loading) {
    [rows addObject:@{@"type": @"loading", @"title": @"Loading...", @"subtitle": @""}];
    self.rows = rows;
    [self.tableView reloadData];
    return;
  }
  if (self.errorMessage.length > 0) {
    [rows addObject:@{@"type": @"info", @"title": self.errorMessage, @"subtitle": @""}];
  }

  if ([self.sectionID isEqualToString:@"account"]) [self buildAccountRows:rows];
  else if ([self.sectionID isEqualToString:@"security"]) [self buildSecurityRows:rows];
  else if ([self.sectionID isEqualToString:@"privacy"]) [self buildPrivacyRows:rows];
  else if ([self.sectionID isEqualToString:@"content"]) [self buildContentRows:rows];
  else if ([self.sectionID isEqualToString:@"content_home"]) [self buildContentHomeRows:rows];
  else if ([self.sectionID isEqualToString:@"content_threads"]) [self buildContentThreadRows:rows];
  else if ([self.sectionID isEqualToString:@"content_moderation"]) [self buildContentModerationRows:rows];
  else if ([self.sectionID isEqualToString:@"notifications"]) [self buildNotificationRows:rows];
  else if ([self.sectionID isEqualToString:@"notification_push"]) [self buildNotificationPushRows:rows];
  else if ([self.sectionID isEqualToString:@"notification_email"]) [self buildNotificationEmailRows:rows];
  else if ([self.sectionID isEqualToString:@"notification_filters"]) [self buildNotificationFilterRows:rows];
  else if ([self.sectionID isEqualToString:@"blue"]) [self buildNotTwitterBlueRows:rows];
  else if ([self.sectionID isEqualToString:@"undo_tweet"]) [self buildUndoTweetRows:rows];
  else [self buildDisplayRows:rows];

  self.rows = rows;
  [self.tableView reloadData];
}

- (void)buildAccountRows:(NSMutableArray<NSDictionary *> *)rows {
  NSDictionary *account = self.account ?: @{};
  NSMutableDictionary *displayAccount = [account mutableCopy];
  if (![displayAccount[@"handle"] isKindOfClass:NSString.class] && [NFBAtprotoSession sharedSession].handle.length > 0) {
    displayAccount[@"handle"] = [NFBAtprotoSession sharedSession].handle;
  }
  NSString *handle = [NFBAtprotoClient displayHandleForProfile:displayAccount];
  NSString *did = [account[@"did"] isKindOfClass:NSString.class] ? account[@"did"] : ([NFBAtprotoSession sharedSession].did ?: @"");
  NSString *email = [account[@"email"] isKindOfClass:NSString.class] ? account[@"email"] : @"";
  [rows addObject:@{@"type": @"info", @"title": @"Account information", @"subtitle": @"See account information and supported account settings."}];
  [rows addObject:@{@"type": @"button", @"title": @"Handle", @"subtitle": handle.length > 0 ? [@"@" stringByAppendingString:handle] : @"Unknown", @"action": @"change_handle"}];
  [rows addObject:@{@"type": @"button", @"title": @"Email address", @"subtitle": [self maskedEmail:email], @"action": @"change_email"}];
  [rows addObject:@{@"type": @"button", @"title": @"Confirm email", @"subtitle": @"Send or enter an email confirmation token.", @"action": @"confirm_email"}];
  [rows addObject:@{@"type": @"info", @"title": @"DID", @"subtitle": did.length > 0 ? did : @"Unknown"}];
}

- (void)buildSecurityRows:(NSMutableArray<NSDictionary *> *)rows {
  NSDictionary *account = self.account ?: @{};
  [rows addObject:@{@"type": @"info", @"title": @"OAuth session", @"subtitle": @"Connected with Bluesky OAuth. This app never asks for an app password."}];
  [rows addObject:@{@"type": @"info", @"title": @"Email two-factor", @"subtitle": [self booleanLabel:account[@"emailAuthFactor"]]}];
  [rows addObject:@{@"type": @"info", @"title": @"Account status", @"subtitle": [self statusLabelForAccount:account]}];
  [rows addObject:@{@"type": @"button", @"title": @"Send password reset", @"subtitle": @"Send a reset email from your PDS.", @"action": @"password_reset_request"}];
  [rows addObject:@{@"type": @"button", @"title": @"Reset password with token", @"subtitle": @"Enter the email token and your new password.", @"action": @"password_reset_confirm"}];
}

- (void)buildPrivacyRows:(NSMutableArray<NSDictionary *> *)rows {
  [rows addObject:@{@"type": @"info", @"title": @"Privacy and safety", @"subtitle": @"Controls here are backed by Bluesky preferences, post interaction settings, the chat declaration record, or local compose settings."}];
  [rows addObject:@{@"type": @"select", @"title": @"Default replies", @"subtitle": [self labelForReplySetting:[self defaultReplySetting]], @"action": @"select_reply"}];
  [rows addObject:@{@"type": @"select", @"title": @"Quote posts", @"subtitle": [self labelForQuoteSetting:[self defaultQuoteSetting]], @"action": @"select_quote"}];
  [rows addObject:@{@"type": @"select", @"title": @"Allow message requests from", @"subtitle": [self labelForChatAllowIncoming:self.chatAllowIncoming], @"action": @"select_chat"}];
  NSArray *muted = [self mutedWords];
  [rows addObject:@{@"type": @"button", @"title": @"Muted words", @"subtitle": muted.count > 0 ? [NSString stringWithFormat:@"%lu muted", (unsigned long)muted.count] : @"Add words, phrases, or tags to mute.", @"action": @"muted_words"}];
}

- (void)buildNotTwitterBlueRows:(NSMutableArray<NSDictionary *> *)rows {
  [rows addObject:@{@"type": @"info", @"title": @"Feature Settings", @"subtitle": @""}];
  [rows addObject:@{@"type": @"button", @"title": @"Undo Tweet", @"subtitle": @"Select which types of Tweets you want to undo before they’re public, plus the length of your undo period.", @"action": @"undo_tweet_detail"}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Reader Mode", @"subtitle": @"Turn long Tweet threads into a continuous reading view.", @"action": @"local_reader_mode", @"value": @(NFBThreadReaderModeEnabled())}];
}

- (void)buildUndoTweetRows:(NSMutableArray<NSDictionary *> *)rows {
  [rows addObject:@{@"type": @"info", @"title": @"Undo Tweet", @"subtitle": @"Select which types of Tweets you want to undo before they’re public, plus the length of your undo period."}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Undo Tweet", @"subtitle": @"Set a timer to undo sent Tweets, and choose which kinds of Tweets you want to undo.", @"action": @"local_undo_tweet", @"value": @(NFBUndoTweetEnabled())}];
  [rows addObject:@{@"type": @"select", @"title": @"Undo Tweet timing", @"subtitle": [self labelForUndoTweetInterval], @"action": @"select_undo_tweet_interval", @"disabled": @(!NFBUndoTweetEnabled())}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Original Tweets", @"subtitle": @"New Tweets that are not replies.", @"action": @"local_undo_tweet_kind_tweet", @"value": @(NFBUndoTweetKindEnabled(@"tweet")), @"disabled": @(!NFBUndoTweetEnabled())}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Replies", @"subtitle": @"Replies to existing Tweets.", @"action": @"local_undo_tweet_kind_reply", @"value": @(NFBUndoTweetKindEnabled(@"reply")), @"disabled": @(!NFBUndoTweetEnabled())}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Quote Tweets", @"subtitle": @"Tweets that quote another Tweet.", @"action": @"local_undo_tweet_kind_quote", @"value": @(NFBUndoTweetKindEnabled(@"quote")), @"disabled": @(!NFBUndoTweetEnabled())}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Threads", @"subtitle": @"Multiple Tweets sent together.", @"action": @"local_undo_tweet_kind_thread", @"value": @(NFBUndoTweetKindEnabled(@"thread")), @"disabled": @(!NFBUndoTweetEnabled())}];
  [rows addObject:@{@"type": @"toggle", @"title": @"View Tweet after sending", @"subtitle": @"", @"action": @"noop_view_after_send", @"value": @YES, @"disabled": @YES}];
}

- (NSString *)labelForUndoTweetInterval {
  return [NSString stringWithFormat:@"%ld seconds", (long)NFBUndoTweetIntervalSeconds()];
}

- (NSArray<NSDictionary *> *)undoTweetIntervalOptions {
  NSMutableArray<NSDictionary *> *options = [NSMutableArray array];
  for (NSNumber *interval in NFBUndoTweetAvailableIntervals()) {
    NSString *value = interval.stringValue;
    [options addObject:@{
      @"value": value,
      @"label": [NSString stringWithFormat:@"%@ seconds", value]
    }];
  }
  return options;
}

- (void)buildContentRows:(NSMutableArray<NSDictionary *> *)rows {
  NSDictionary *feed = [self feedViewPreference];
  NSDictionary *thread = [self threadViewPreference];
  [rows addObject:@{@"type": @"info", @"title": @"Content you see", @"subtitle": @"These preferences come from app.bsky.actor.getPreferences."}];
  [rows addObject:@{@"type": @"button", @"title": @"Home feed", @"subtitle": [self summaryForHomeFeedPreference:feed], @"action": @"content_home"}];
  [rows addObject:@{@"type": @"button", @"title": @"Threads", @"subtitle": [self summaryForThreadPreference:thread], @"action": @"content_threads"}];
  NSArray *interests = [self interests];
  [rows addObject:@{@"type": @"button", @"title": @"Interests", @"subtitle": interests.count > 0 ? [NSString stringWithFormat:@"%lu selected", (unsigned long)interests.count] : @"Choose Topics used by Bluesky Interests.", @"action": @"interests"}];
  [rows addObject:@{@"type": @"button", @"title": @"Bluesky Moderation Service", @"subtitle": [self summaryForModerationPreferences], @"action": @"content_moderation"}];
}

- (void)buildContentHomeRows:(NSMutableArray<NSDictionary *> *)rows {
  NSDictionary *feed = [self feedViewPreference];
  [rows addObject:@{@"type": @"info", @"title": @"Home feed", @"subtitle": @"Choose what appears in your Home timeline."}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Hide replies", @"subtitle": @"Hide replies in Home.", @"action": @"feed_hideReplies", @"value": @([feed[@"hideReplies"] boolValue])}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Hide replies from people you do not follow", @"subtitle": @"Applies to home feed replies.", @"action": @"feed_hideRepliesByUnfollowed", @"value": @([feed[@"hideRepliesByUnfollowed"] boolValue])}];
  [rows addObject:@{@"type": @"select", @"title": @"Minimum likes for replies", @"subtitle": [NSString stringWithFormat:@"%ld", (long)[feed[@"hideRepliesByLikeCount"] integerValue]], @"action": @"select_reply_like_count"}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Hide reposts", @"subtitle": @"", @"action": @"feed_hideReposts", @"value": @([feed[@"hideReposts"] boolValue])}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Hide quote posts", @"subtitle": @"", @"action": @"feed_hideQuotePosts", @"value": @([feed[@"hideQuotePosts"] boolValue])}];
}

- (void)buildContentThreadRows:(NSMutableArray<NSDictionary *> *)rows {
  NSDictionary *thread = [self threadViewPreference];
  [rows addObject:@{@"type": @"info", @"title": @"Threads", @"subtitle": @"Choose how replies are sorted and ranked in conversations."}];
  NSString *sort = [thread[@"sort"] isKindOfClass:NSString.class] ? thread[@"sort"] : @"hotness";
  [rows addObject:@{@"type": @"select", @"title": @"Reply sort", @"subtitle": [self labelForThreadSort:sort], @"action": @"select_thread_sort"}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Prioritize people you follow", @"subtitle": @"", @"action": @"thread_prioritizeFollowedUsers", @"value": @([thread[@"prioritizeFollowedUsers"] boolValue])}];
}

- (void)buildContentModerationRows:(NSMutableArray<NSDictionary *> *)rows {
  [rows addObject:@{@"type": @"info", @"title": @"Bluesky Moderation Service", @"subtitle": @"Control labels with Off, Warn, and Hide."}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Adult content", @"subtitle": @"Enable adult-content handling for label preferences.", @"action": @"pref_adult", @"value": @([self adultContentEnabled])}];
  for (NSDictionary *config in [self contentLabelConfigs]) {
    NSString *label = config[@"label"];
    NSString *title = config[@"title"];
    NSString *visibility = [self contentLabelVisibilityForConfig:config];
    [rows addObject:@{@"type": @"select", @"title": title ?: label, @"subtitle": [self labelForContentVisibility:visibility], @"action": [@"label_" stringByAppendingString:label ?: @""]}];
  }
}

- (NSString *)summaryForHomeFeedPreference:(NSDictionary *)feed {
  NSMutableArray *parts = [NSMutableArray array];
  if ([feed[@"hideReplies"] boolValue]) [parts addObject:@"Replies hidden"];
  else if ([feed[@"hideRepliesByUnfollowed"] boolValue]) [parts addObject:@"Unfollowed replies hidden"];
  NSInteger likeCount = [feed[@"hideRepliesByLikeCount"] integerValue];
  if (likeCount > 0) [parts addObject:[NSString stringWithFormat:@"Replies need %ld likes", (long)likeCount]];
  if ([feed[@"hideReposts"] boolValue]) [parts addObject:@"Reposts hidden"];
  if ([feed[@"hideQuotePosts"] boolValue]) [parts addObject:@"Quotes hidden"];
  return parts.count > 0 ? [parts componentsJoinedByString:@" · "] : @"Replies, reposts, and quote posts.";
}

- (NSString *)summaryForThreadPreference:(NSDictionary *)thread {
  NSString *sort = [thread[@"sort"] isKindOfClass:NSString.class] ? thread[@"sort"] : @"hotness";
  NSString *label = [self labelForThreadSort:sort];
  if ([thread[@"prioritizeFollowedUsers"] boolValue]) return [label stringByAppendingString:@" · Prioritize followed"];
  return label;
}

- (NSString *)summaryForModerationPreferences {
  NSInteger hidden = 0;
  NSInteger warned = 0;
  for (NSDictionary *config in [self contentLabelConfigs]) {
    NSString *visibility = [self contentLabelVisibilityForConfig:config];
    if ([visibility isEqualToString:@"hide"]) hidden++;
    else if ([visibility isEqualToString:@"warn"]) warned++;
  }
  NSString *adult = [self adultContentEnabled] ? @"Adult content on" : @"Adult content off";
  return [NSString stringWithFormat:@"%@ · %ld hidden · %ld warned", adult, (long)hidden, (long)warned];
}

- (void)buildNotificationRows:(NSMutableArray<NSDictionary *> *)rows {
  BOOL hasSession = [[NFBAtprotoSession sharedSession] hasSession];
  [rows addObject:@{@"type": @"info", @"title": @"Notifications", @"subtitle": @"Choose push, email, and filtering settings for the Notifications timeline."}];
  [rows addObject:@{@"type": @"button", @"title": @"Push notifications", @"subtitle": [self pushNotificationSettingsSummary], @"action": @"notification_push_detail", @"disabled": @(!hasSession)}];
  [rows addObject:@{@"type": @"button", @"title": @"Email notifications", @"subtitle": [self emailNotificationSettingsSummary], @"action": @"notification_email_detail"}];
  [rows addObject:@{@"type": @"button", @"title": @"Advanced filters", @"subtitle": [self advancedNotificationFiltersSummary], @"action": @"notification_filters_detail"}];
}

- (void)buildNotificationPushRows:(NSMutableArray<NSDictionary *> *)rows {
  BOOL canEdit = [[NFBAtprotoSession sharedSession] hasSession] && self.errorMessage.length == 0;
  [rows addObject:@{@"type": @"info", @"title": @"Push notifications", @"subtitle": @"Choose which notifications appear in the app and which can be sent to your device."}];
  NSArray<NSDictionary *> *definitions = [self notificationDefinitions];
  for (NSDictionary *definition in definitions) {
    NSString *key = definition[@"key"];
    NSDictionary *pref = [self notificationPreferenceForKey:key];
    if (pref.count == 0) continue;
    NSString *include = [pref[@"include"] isKindOfClass:NSString.class] ? pref[@"include"] : @"";
    if (include.length > 0) {
      [rows addObject:@{@"type": @"select", @"title": [NSString stringWithFormat:@"%@ from", definition[@"title"]], @"subtitle": [self labelForNotificationInclude:include chat:[key isEqualToString:@"chat"]], @"action": [@"notif_include_" stringByAppendingString:key], @"disabled": @(!canEdit)}];
    }
    [rows addObject:@{@"type": @"toggle", @"title": [NSString stringWithFormat:@"%@ in Notifications", definition[@"title"]], @"subtitle": definition[@"description"] ?: @"", @"action": [@"notif_list_" stringByAppendingString:key], @"value": @([pref[@"list"] boolValue]), @"disabled": @(!canEdit)}];
    [rows addObject:@{@"type": @"toggle", @"title": [NSString stringWithFormat:@"%@ push", definition[@"title"]], @"subtitle": @"", @"action": [@"notif_push_" stringByAppendingString:key], @"value": @([pref[@"push"] boolValue]), @"disabled": @(!canEdit)}];
  }
}

- (void)buildNotificationEmailRows:(NSMutableArray<NSDictionary *> *)rows {
  BOOL enabled = [self emailNotificationSettingEnabledForKey:NFBNotificationEmailEnabledKey];
  [rows addObject:@{@"type": @"info", @"title": @"Email notifications", @"subtitle": @"These settings mirror Twitter's email notification screen locally until ATProto exposes account email notification preferences."}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Email notifications", @"subtitle": @"Turn local email-notification preferences on or off.", @"action": @"local_notification_email_enabled", @"value": @(enabled)}];
  NSArray<NSDictionary *> *definitions = [self emailNotificationDefinitions];
  for (NSDictionary *definition in definitions) {
    NSString *key = definition[@"key"];
    NSString *action = [@"local_notification_email_" stringByAppendingString:definition[@"action"] ?: @""];
    [rows addObject:@{@"type": @"toggle", @"title": definition[@"title"] ?: @"Email notification", @"subtitle": definition[@"description"] ?: @"", @"action": action, @"value": @([self emailNotificationSettingEnabledForKey:key]), @"disabled": @(!enabled)}];
  }
}

- (void)buildNotificationFilterRows:(NSMutableArray<NSDictionary *> *)rows {
  [rows addObject:@{@"type": @"info", @"title": @"Advanced filters", @"subtitle": @"Reduce lower-signal activity notifications before they appear in your Notifications timeline."}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Quality filter", @"subtitle": @"Filter activity notifications with incomplete account details.", @"action": @"local_notification_filter_quality", @"value": @([self localNotificationFilterEnabledForKey:NFBNotificationFilterQualityKey])}];
  [rows addObject:@{@"type": @"toggle", @"title": @"People you do not follow", @"subtitle": @"Hide likes, reposts, follows, and other activity from accounts you do not follow.", @"action": @"local_notification_filter_you_do_not_follow", @"value": @([self localNotificationFilterEnabledForKey:NFBNotificationFilterYouDoNotFollowKey])}];
  [rows addObject:@{@"type": @"toggle", @"title": @"People who do not follow you", @"subtitle": @"Hide activity from accounts that do not follow you.", @"action": @"local_notification_filter_not_following_you", @"value": @([self localNotificationFilterEnabledForKey:NFBNotificationFilterNotFollowingYouKey])}];
  [rows addObject:@{@"type": @"toggle", @"title": @"New accounts", @"subtitle": @"Hide activity from accounts created in the last 30 days.", @"action": @"local_notification_filter_new_accounts", @"value": @([self localNotificationFilterEnabledForKey:NFBNotificationFilterNewAccountsKey])}];
  [rows addObject:@{@"type": @"toggle", @"title": @"Default profile photos", @"subtitle": @"Hide activity from accounts without a custom profile photo.", @"action": @"local_notification_filter_default_avatar", @"value": @([self localNotificationFilterEnabledForKey:NFBNotificationFilterDefaultAvatarKey])}];
}

- (void)buildDisplayRows:(NSMutableArray<NSDictionary *> *)rows {
  BOOL hideSuffix = [NSUserDefaults.standardUserDefaults boolForKey:NFBHideBskySocialSuffixKey];
  [rows addObject:@{@"type": @"button", @"title": @"Display", @"subtitle": @"Change color, background, and font sizing.", @"action": @"show_display"}];
  [rows addObject:@{@"type": @"button", @"title": @"App icon", @"subtitle": @"Choose a custom Not Twitter icon.", @"action": @"show_app_icon"}];
  [rows addObject:@{@"type": @"toggle", @"key": NFBHideBskySocialSuffixKey, @"title": @"Hide .bsky.social suffixes", @"subtitle": @"Shorten only generic Bluesky handles in visible usernames.", @"action": @"local_hide_suffix", @"value": @(hideSuffix)}];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  (void)tableView;
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return (NSInteger)self.rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NFBSettingsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"settings" forIndexPath:indexPath];
  [cell configureWithItem:self.rows[(NSUInteger)indexPath.row]
                      row:indexPath.row
                   target:self
                   action:@selector(toggleChanged:)];
  return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return [[UIView alloc] initWithFrame:CGRectZero];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return 0.01;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSDictionary *row = self.rows[(NSUInteger)indexPath.row];
  NSString *action = [row[@"action"] isKindOfClass:NSString.class] ? row[@"action"] : @"";
  if (action.length == 0) return;
  if ([action isEqualToString:@"show_display"]) {
    [self.navigationController pushViewController:[[NFBDisplaySettingsViewController alloc] init] animated:YES];
  } else if ([action isEqualToString:@"show_app_icon"]) {
    [self.navigationController pushViewController:[[NFBAppIconSettingsViewController alloc] init] animated:YES];
  } else if ([action isEqualToString:@"select_reply"]) {
    [self showChoiceWithTitle:@"Default replies" options:[self replyOptions] current:[self defaultReplySetting] completion:^(NSString *value) { [self updateDefaultReply:value]; }];
  } else if ([action isEqualToString:@"select_undo_tweet_interval"]) {
    NSString *current = [NSString stringWithFormat:@"%ld", (long)NFBUndoTweetIntervalSeconds()];
    [self showChoiceWithTitle:@"Undo Tweet timing" options:[self undoTweetIntervalOptions] current:current completion:^(NSString *value) {
      NFBSetUndoTweetIntervalSeconds(value.integerValue);
      [self rebuildRows];
    }];
  } else if ([action isEqualToString:@"undo_tweet_detail"]) {
    NFBSettingsDetailViewController *detail = [[NFBSettingsDetailViewController alloc] initWithSectionID:@"undo_tweet" title:@"Undo Tweet"];
    [self.navigationController pushViewController:detail animated:YES];
  } else if ([action isEqualToString:@"notification_push_detail"]) {
    NFBSettingsDetailViewController *detail = [[NFBSettingsDetailViewController alloc] initWithSectionID:@"notification_push" title:@"Push notifications"];
    [self.navigationController pushViewController:detail animated:YES];
  } else if ([action isEqualToString:@"notification_email_detail"]) {
    NFBSettingsDetailViewController *detail = [[NFBSettingsDetailViewController alloc] initWithSectionID:@"notification_email" title:@"Email notifications"];
    [self.navigationController pushViewController:detail animated:YES];
  } else if ([action isEqualToString:@"notification_filters_detail"]) {
    NFBSettingsDetailViewController *detail = [[NFBSettingsDetailViewController alloc] initWithSectionID:@"notification_filters" title:@"Advanced filters"];
    [self.navigationController pushViewController:detail animated:YES];
  } else if ([action isEqualToString:@"select_quote"]) {
    [self showChoiceWithTitle:@"Quote posts" options:[self quoteOptions] current:[self defaultQuoteSetting] completion:^(NSString *value) { [self updateDefaultQuote:value]; }];
  } else if ([action isEqualToString:@"select_chat"]) {
    [self showChoiceWithTitle:@"Allow message requests from" options:[self chatOptions] current:self.chatAllowIncoming completion:^(NSString *value) { [self updateChatAllowIncoming:value]; }];
  } else if ([action isEqualToString:@"select_thread_sort"]) {
    [self showChoiceWithTitle:@"Reply sort" options:[self threadSortOptions] current:[self threadViewPreference][@"sort"] ?: @"hotness" completion:^(NSString *value) { [self updateThreadPreferenceKey:@"sort" value:value]; }];
  } else if ([action isEqualToString:@"select_reply_like_count"]) {
    [self promptForNumberWithTitle:@"Minimum likes for replies" current:[[self feedViewPreference][@"hideRepliesByLikeCount"] integerValue] completion:^(NSInteger value) { [self updateFeedPreferenceKey:@"hideRepliesByLikeCount" value:@(value)]; }];
  } else if ([action isEqualToString:@"muted_words"]) {
    [self showMutedWordsMenu];
  } else if ([action isEqualToString:@"interests"]) {
    [self.navigationController pushViewController:[[NFBTopicsSettingsViewController alloc] init] animated:YES];
  } else if ([action isEqualToString:@"content_home"] || [action isEqualToString:@"content_threads"] || [action isEqualToString:@"content_moderation"]) {
    NSString *title = [row[@"title"] isKindOfClass:NSString.class] ? row[@"title"] : @"Content you see";
    NFBSettingsDetailViewController *detail = [[NFBSettingsDetailViewController alloc] initWithSectionID:action title:title];
    [self.navigationController pushViewController:detail animated:YES];
  } else if ([action isEqualToString:@"change_handle"]) {
    [self promptForTextWithTitle:@"Change handle" placeholder:@"handle.bsky.social" secure:NO completion:^(NSString *value) { [self updateHandle:value]; }];
  } else if ([action isEqualToString:@"change_email"]) {
    [self promptForTextWithTitle:@"Change email" placeholder:@"email@example.com" secure:NO completion:^(NSString *value) { [self updateEmail:value]; }];
  } else if ([action isEqualToString:@"confirm_email"]) {
    [self showEmailConfirmationMenu];
  } else if ([action isEqualToString:@"password_reset_request"]) {
    [self promptForTextWithTitle:@"Send password reset" placeholder:@"email@example.com" secure:NO completion:^(NSString *value) { [self requestPasswordReset:value]; }];
  } else if ([action isEqualToString:@"password_reset_confirm"]) {
    [self promptForPasswordResetConfirmation];
  } else if ([action hasPrefix:@"label_"]) {
    NSString *label = [action substringFromIndex:[@"label_" length]];
    NSDictionary *config = [self contentLabelConfigForLabel:label];
    [self showChoiceWithTitle:config[@"title"] ?: label options:[self labelVisibilityOptions] current:[self contentLabelVisibilityForConfig:config] completion:^(NSString *value) { [self updateContentLabel:config visibility:value]; }];
  } else if ([action hasPrefix:@"notif_include_"]) {
    NSString *key = [action substringFromIndex:[@"notif_include_" length]];
    NSDictionary *pref = [self notificationPreferenceForKey:key];
    [self showChoiceWithTitle:@"Notifications from" options:[self notificationIncludeOptionsForChat:[key isEqualToString:@"chat"]] current:pref[@"include"] ?: @"all" completion:^(NSString *value) { [self updateNotificationKey:key field:@"include" value:value]; }];
  }
}

- (void)toggleChanged:(UISwitch *)sender {
  NSInteger rowIndex = sender.tag;
  if (rowIndex < 0 || rowIndex >= (NSInteger)self.rows.count) return;
  NSDictionary *row = self.rows[(NSUInteger)rowIndex];
  NSString *action = [row[@"action"] isKindOfClass:NSString.class] ? row[@"action"] : @"";
  if ([action isEqualToString:@"local_hide_suffix"]) {
    [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:NFBHideBskySocialSuffixKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:NFBThemeDidChangeNotification object:nil];
    return;
  }
  if ([action isEqualToString:@"local_undo_tweet"]) {
    NFBSetUndoTweetEnabled(sender.isOn);
    [self rebuildRows];
    return;
  }
  if ([action isEqualToString:@"local_reader_mode"]) {
    NFBSetThreadReaderModeEnabled(sender.isOn);
    [self rebuildRows];
    return;
  }
  if ([action hasPrefix:@"local_undo_tweet_kind_"]) {
    NSString *kind = [action substringFromIndex:[@"local_undo_tweet_kind_" length]];
    NFBSetUndoTweetKindEnabled(kind, sender.isOn);
    return;
  }
  if ([action hasPrefix:@"local_notification_filter_"]) {
    NSString *key = [self notificationFilterDefaultsKeyForAction:action];
    if (key.length > 0) {
      [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:key];
      [NSUserDefaults.standardUserDefaults synchronize];
      [[NSNotificationCenter defaultCenter] postNotificationName:NFBNotificationAdvancedFiltersDidChangeNotification object:nil];
      [self rebuildRows];
    }
    return;
  }
  if ([action hasPrefix:@"local_notification_email_"]) {
    NSString *key = [self notificationEmailDefaultsKeyForAction:action];
    if (key.length > 0) {
      [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:key];
      [NSUserDefaults.standardUserDefaults synchronize];
      [self rebuildRows];
    }
    return;
  }
  if ([action isEqualToString:@"pref_adult"]) [self updateAdultContent:sender.isOn];
  else if ([action hasPrefix:@"feed_"]) [self updateFeedPreferenceKey:[action substringFromIndex:[@"feed_" length]] value:@(sender.isOn)];
  else if ([action hasPrefix:@"thread_"]) [self updateThreadPreferenceKey:[action substringFromIndex:[@"thread_" length]] value:@(sender.isOn)];
  else if ([action hasPrefix:@"notif_list_"]) [self updateNotificationKey:[action substringFromIndex:[@"notif_list_" length]] field:@"list" value:@(sender.isOn)];
  else if ([action hasPrefix:@"notif_push_"]) [self updateNotificationKey:[action substringFromIndex:[@"notif_push_" length]] field:@"push" value:@(sender.isOn)];
}

- (NSDictionary *)preferenceForType:(NSString *)type matching:(BOOL (^)(NSDictionary *preference))matching {
  for (NSDictionary *preference in self.preferences) {
    if (![preference[@"$type"] isEqualToString:type]) continue;
    if (!matching || matching(preference)) return preference;
  }
  return nil;
}

- (void)replacePreference:(NSDictionary *)next type:(NSString *)type matching:(BOOL (^)(NSDictionary *preference))matching {
  NSUInteger index = NSNotFound;
  for (NSUInteger i = 0; i < self.preferences.count; i++) {
    NSDictionary *preference = self.preferences[i];
    if (![preference[@"$type"] isEqualToString:type]) continue;
    if (!matching || matching(preference)) {
      index = i;
      break;
    }
  }
  if (index == NSNotFound) [self.preferences addObject:[next mutableCopy]];
  else self.preferences[index] = [next mutableCopy];
}

- (NSDictionary *)adultContentPreference {
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#adultContentPref" matching:nil];
  return preference ?: @{@"$type": @"app.bsky.actor.defs#adultContentPref", @"enabled": @NO};
}

- (BOOL)adultContentEnabled {
  return [[self adultContentPreference][@"enabled"] boolValue];
}

- (NSDictionary *)feedViewPreference {
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#feedViewPref" matching:^BOOL(NSDictionary *preference) {
    NSString *feed = [preference[@"feed"] isKindOfClass:NSString.class] ? preference[@"feed"] : @"home";
    return feed.length == 0 || [feed isEqualToString:@"home"];
  }];
  return preference ?: @{@"$type": @"app.bsky.actor.defs#feedViewPref", @"feed": @"home", @"hideReplies": @NO, @"hideRepliesByUnfollowed": @NO, @"hideRepliesByLikeCount": @0, @"hideReposts": @NO, @"hideQuotePosts": @NO};
}

- (NSDictionary *)threadViewPreference {
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#threadViewPref" matching:nil];
  return preference ?: @{@"$type": @"app.bsky.actor.defs#threadViewPref", @"sort": @"hotness", @"prioritizeFollowedUsers": @NO};
}

- (NSDictionary *)postInteractionPreference {
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#postInteractionSettingsPref" matching:nil];
  return preference ?: @{@"$type": @"app.bsky.actor.defs#postInteractionSettingsPref"};
}

- (NSArray *)mutedWords {
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#mutedWordsPref" matching:nil];
  return [preference[@"items"] isKindOfClass:NSArray.class] ? preference[@"items"] : @[];
}

- (NSArray *)interests {
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#interestsPref" matching:nil];
  return [preference[@"tags"] isKindOfClass:NSArray.class] ? preference[@"tags"] : @[];
}

- (NSString *)defaultReplySetting {
  NSArray *rules = [self postInteractionPreference][@"threadgateAllowRules"];
  if (![rules isKindOfClass:NSArray.class]) return @"everyone";
  if (rules.count == 0) return @"nobody";
  if (rules.count != 1) return @"custom";
  NSString *type = [rules.firstObject[@"$type"] isKindOfClass:NSString.class] ? rules.firstObject[@"$type"] : @"";
  if ([type isEqualToString:@"app.bsky.feed.threadgate#followingRule"]) return @"following";
  if ([type isEqualToString:@"app.bsky.feed.threadgate#followerRule"]) return @"followers";
  if ([type isEqualToString:@"app.bsky.feed.threadgate#mentionRule"]) return @"mentioned";
  return @"custom";
}

- (NSString *)defaultQuoteSetting {
  NSArray *rules = [self postInteractionPreference][@"postgateEmbeddingRules"];
  if (![rules isKindOfClass:NSArray.class] || rules.count == 0) return @"enabled";
  if (rules.count == 1 && [rules.firstObject[@"$type"] isEqualToString:@"app.bsky.feed.postgate#disableRule"]) return @"disabled";
  return @"custom";
}

- (NSArray *)replyRulesForSetting:(NSString *)setting {
  if ([setting isEqualToString:@"nobody"]) return @[];
  if ([setting isEqualToString:@"following"]) return @[@{@"$type": @"app.bsky.feed.threadgate#followingRule"}];
  if ([setting isEqualToString:@"followers"]) return @[@{@"$type": @"app.bsky.feed.threadgate#followerRule"}];
  if ([setting isEqualToString:@"mentioned"]) return @[@{@"$type": @"app.bsky.feed.threadgate#mentionRule"}];
  return nil;
}

- (NSArray *)quoteRulesForSetting:(NSString *)setting {
  if ([setting isEqualToString:@"disabled"]) return @[@{@"$type": @"app.bsky.feed.postgate#disableRule"}];
  return nil;
}

- (void)savePreferencesAndRebuild {
  self.loading = YES;
  [self rebuildRows];
  [self putPreferencesWithCompletion:^(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!error) NFBModerationCachePreferences(self.preferences ?: @[]);
      self.loading = NO;
      self.errorMessage = error.localizedDescription;
      [self rebuildRows];
    });
  }];
}

- (void)updateAdultContent:(BOOL)enabled {
  NSMutableDictionary *preference = [[self adultContentPreference] mutableCopy];
  preference[@"enabled"] = @(enabled);
  [self replacePreference:preference type:@"app.bsky.actor.defs#adultContentPref" matching:nil];
  [self savePreferencesAndRebuild];
}

- (void)updateFeedPreferenceKey:(NSString *)key value:(id)value {
  NSMutableDictionary *preference = [[self feedViewPreference] mutableCopy];
  preference[@"$type"] = @"app.bsky.actor.defs#feedViewPref";
  preference[@"feed"] = @"home";
  preference[key] = value ?: @NO;
  [self replacePreference:preference type:@"app.bsky.actor.defs#feedViewPref" matching:^BOOL(NSDictionary *candidate) {
    NSString *feed = [candidate[@"feed"] isKindOfClass:NSString.class] ? candidate[@"feed"] : @"home";
    return feed.length == 0 || [feed isEqualToString:@"home"];
  }];
  [self savePreferencesAndRebuild];
}

- (void)updateThreadPreferenceKey:(NSString *)key value:(id)value {
  NSMutableDictionary *preference = [[self threadViewPreference] mutableCopy];
  preference[@"$type"] = @"app.bsky.actor.defs#threadViewPref";
  preference[key] = value ?: @NO;
  [self replacePreference:preference type:@"app.bsky.actor.defs#threadViewPref" matching:nil];
  [self savePreferencesAndRebuild];
}

- (void)updateDefaultReply:(NSString *)setting {
  NSMutableDictionary *preference = [[self postInteractionPreference] mutableCopy];
  preference[@"$type"] = @"app.bsky.actor.defs#postInteractionSettingsPref";
  NSArray *rules = [self replyRulesForSetting:setting];
  if (rules) preference[@"threadgateAllowRules"] = rules;
  else [preference removeObjectForKey:@"threadgateAllowRules"];
  [self replacePreference:preference type:@"app.bsky.actor.defs#postInteractionSettingsPref" matching:nil];
  [self savePreferencesAndRebuild];
}

- (void)updateDefaultQuote:(NSString *)setting {
  NSMutableDictionary *preference = [[self postInteractionPreference] mutableCopy];
  preference[@"$type"] = @"app.bsky.actor.defs#postInteractionSettingsPref";
  NSArray *rules = [self quoteRulesForSetting:setting];
  if (rules) preference[@"postgateEmbeddingRules"] = rules;
  else [preference removeObjectForKey:@"postgateEmbeddingRules"];
  [self replacePreference:preference type:@"app.bsky.actor.defs#postInteractionSettingsPref" matching:nil];
  [self savePreferencesAndRebuild];
}

- (void)updateChatAllowIncoming:(NSString *)allowIncoming {
  NSString *did = [NFBAtprotoSession sharedSession].did ?: @"";
  if (did.length == 0) return;
  self.loading = YES;
  [self rebuildRows];
  NSDictionary *record = @{@"$type": NFBChatDeclarationCollection, @"allowIncoming": [self normalizedChatAllowIncoming:allowIncoming]};
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.repo.putRecord"
                                      service:nil
                                         body:@{@"repo": did, @"collection": NFBChatDeclarationCollection, @"rkey": @"self", @"record": record}
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)value;
    (void)response;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.chatAllowIncoming = [self normalizedChatAllowIncoming:allowIncoming];
      self.loading = NO;
      self.errorMessage = error.localizedDescription;
      [self rebuildRows];
    });
  }];
}

- (void)updateContentLabel:(NSDictionary *)config visibility:(NSString *)visibility {
  NSString *label = config[@"label"];
  if (label.length == 0) return;
  NSMutableDictionary *preference = [@{@"$type": @"app.bsky.actor.defs#contentLabelPref", @"label": label, @"visibility": visibility ?: @"warn"} mutableCopy];
  NSString *labelerDid = config[@"labelerDid"];
  if (labelerDid.length > 0) preference[@"labelerDid"] = labelerDid;
  [self replacePreference:preference type:@"app.bsky.actor.defs#contentLabelPref" matching:^BOOL(NSDictionary *candidate) {
    NSString *candidateLabel = [candidate[@"label"] isKindOfClass:NSString.class] ? candidate[@"label"] : @"";
    NSString *candidateLabeler = [candidate[@"labelerDid"] isKindOfClass:NSString.class] ? candidate[@"labelerDid"] : @"";
    NSString *targetLabeler = labelerDid ?: @"";
    return [candidateLabel isEqualToString:label] && [candidateLabeler isEqualToString:targetLabeler];
  }];
  [self savePreferencesAndRebuild];
}

- (NSDictionary *)notificationPreferenceForKey:(NSString *)key {
  NSDictionary *pref = [self.notificationPreferences[key] isKindOfClass:NSDictionary.class] ? self.notificationPreferences[key] : nil;
  if (pref) return pref;
  return @{@"include": [key isEqualToString:@"chat"] ? @"accepted" : @"all", @"list": @YES, @"push": @YES};
}

- (BOOL)localNotificationFilterEnabledForKey:(NSString *)key {
  return key.length > 0 && [NSUserDefaults.standardUserDefaults boolForKey:key];
}

- (NSString *)notificationFilterDefaultsKeyForAction:(NSString *)action {
  if ([action isEqualToString:@"local_notification_filter_quality"]) return NFBNotificationFilterQualityKey;
  if ([action isEqualToString:@"local_notification_filter_you_do_not_follow"]) return NFBNotificationFilterYouDoNotFollowKey;
  if ([action isEqualToString:@"local_notification_filter_not_following_you"]) return NFBNotificationFilterNotFollowingYouKey;
  if ([action isEqualToString:@"local_notification_filter_new_accounts"]) return NFBNotificationFilterNewAccountsKey;
  if ([action isEqualToString:@"local_notification_filter_default_avatar"]) return NFBNotificationFilterDefaultAvatarKey;
  return @"";
}

- (NSString *)advancedNotificationFiltersSummary {
  NSMutableArray<NSString *> *enabled = [NSMutableArray array];
  if ([self localNotificationFilterEnabledForKey:NFBNotificationFilterQualityKey]) [enabled addObject:@"Quality filter"];
  if ([self localNotificationFilterEnabledForKey:NFBNotificationFilterYouDoNotFollowKey]) [enabled addObject:@"People you do not follow"];
  if ([self localNotificationFilterEnabledForKey:NFBNotificationFilterNotFollowingYouKey]) [enabled addObject:@"People who do not follow you"];
  if ([self localNotificationFilterEnabledForKey:NFBNotificationFilterNewAccountsKey]) [enabled addObject:@"New accounts"];
  if ([self localNotificationFilterEnabledForKey:NFBNotificationFilterDefaultAvatarKey]) [enabled addObject:@"Default profile photos"];
  if (enabled.count == 0) return @"Quality filter and account-based notification filters.";
  if (enabled.count == 1) return [enabled.firstObject stringByAppendingString:@" on"];
  return [NSString stringWithFormat:@"%lu filters on", (unsigned long)enabled.count];
}

- (NSString *)pushNotificationSettingsSummary {
  if (![[NFBAtprotoSession sharedSession] hasSession]) return @"Sign in to manage push notification settings.";
  NSInteger pushEnabled = 0;
  NSInteger timelineEnabled = 0;
  NSInteger total = 0;
  for (NSDictionary *definition in [self notificationDefinitions]) {
    NSString *key = definition[@"key"];
    NSDictionary *pref = [self notificationPreferenceForKey:key];
    if (pref.count == 0) continue;
    total++;
    if ([pref[@"push"] boolValue]) pushEnabled++;
    if ([pref[@"list"] boolValue]) timelineEnabled++;
  }
  if (total == 0) return @"Choose device and timeline notification categories.";
  return [NSString stringWithFormat:@"%ld of %ld push · %ld in timeline", (long)pushEnabled, (long)total, (long)timelineEnabled];
}

- (NSArray<NSDictionary *> *)emailNotificationDefinitions {
  return @[
    @{@"key": NFBNotificationEmailActivityKey, @"action": @"activity", @"title": @"New notifications", @"description": @"A periodic summary of unread activity."},
    @{@"key": NFBNotificationEmailMentionsKey, @"action": @"mentions", @"title": @"Mentions and replies", @"description": @"Posts that mention you and replies to your posts."},
    @{@"key": NFBNotificationEmailFollowersKey, @"action": @"followers", @"title": @"New followers", @"description": @"People who follow your account."},
    @{@"key": NFBNotificationEmailMessagesKey, @"action": @"messages", @"title": @"Direct messages", @"description": @"Unread conversation activity."},
    @{@"key": NFBNotificationEmailProductKey, @"action": @"product", @"title": @"Product updates", @"description": @"News, tips, and feature announcements."}
  ];
}

- (BOOL)defaultEmailNotificationSettingForKey:(NSString *)key {
  if ([key isEqualToString:NFBNotificationEmailEnabledKey]) return NO;
  return YES;
}

- (BOOL)emailNotificationSettingEnabledForKey:(NSString *)key {
  if (key.length == 0) return NO;
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  if ([defaults objectForKey:key]) return [defaults boolForKey:key];
  return [self defaultEmailNotificationSettingForKey:key];
}

- (NSString *)notificationEmailDefaultsKeyForAction:(NSString *)action {
  if ([action isEqualToString:@"local_notification_email_enabled"]) return NFBNotificationEmailEnabledKey;
  NSString *prefix = @"local_notification_email_";
  if (![action hasPrefix:prefix]) return @"";
  NSString *suffix = [action substringFromIndex:prefix.length];
  for (NSDictionary *definition in [self emailNotificationDefinitions]) {
    NSString *definitionAction = [definition[@"action"] isKindOfClass:NSString.class] ? definition[@"action"] : @"";
    if ([definitionAction isEqualToString:suffix]) return definition[@"key"] ?: @"";
  }
  return @"";
}

- (NSString *)emailNotificationSettingsSummary {
  if (![self emailNotificationSettingEnabledForKey:NFBNotificationEmailEnabledKey]) return @"Off";
  NSInteger enabled = 0;
  NSArray<NSDictionary *> *definitions = [self emailNotificationDefinitions];
  for (NSDictionary *definition in definitions) {
    NSString *key = definition[@"key"];
    if ([self emailNotificationSettingEnabledForKey:key]) enabled++;
  }
  if (enabled == 0) return @"No email categories on";
  if (enabled == (NSInteger)definitions.count) return @"All email categories on";
  return [NSString stringWithFormat:@"%ld of %lu categories on", (long)enabled, (unsigned long)definitions.count];
}

- (void)updateNotificationKey:(NSString *)key field:(NSString *)field value:(id)value {
  NSMutableDictionary *next = [[self notificationPreferenceForKey:key] mutableCopy];
  next[field] = value ?: @NO;
  self.loading = YES;
  [self rebuildRows];
  [[NFBAtprotoSession sharedSession] xrpcPOSTViaAppViewProxy:@"app.bsky.notification.putPreferencesV2"
                                                        body:@{key: next}
                                                  completion:^(id responseValue, NSHTTPURLResponse *response, NSError *error) {
    (void)responseValue;
    (void)response;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSMutableDictionary *all = [self.notificationPreferences mutableCopy] ?: [NSMutableDictionary dictionary];
      all[key] = next;
      self.notificationPreferences = all;
      self.loading = NO;
      self.errorMessage = error.localizedDescription;
      [self rebuildRows];
    });
  }];
}

- (void)updateHandle:(NSString *)handle {
  NSString *safe = [[handle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] stringByReplacingOccurrencesOfString:@"@" withString:@""];
  if (safe.length == 0) return;
  self.loading = YES;
  [self rebuildRows];
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.identity.updateHandle"
                                      service:nil
                                         body:@{@"handle": safe.lowercaseString}
                                authenticated:YES
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)value;
    (void)response;
    [self fetchAccountWithCompletion:^(NSError *fetchError) {
      dispatch_async(dispatch_get_main_queue(), ^{
        self.loading = NO;
        self.errorMessage = error.localizedDescription ?: fetchError.localizedDescription;
        [self rebuildRows];
      });
    }];
  }];
}

- (void)updateEmail:(NSString *)email {
  NSString *safe = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (safe.length == 0) return;
  [self promptForTextWithTitle:@"Email token" placeholder:@"Leave blank if none required" secure:NO completion:^(NSString *token) {
    NSMutableDictionary *body = [@{@"email": safe} mutableCopy];
    if (token.length > 0) body[@"token"] = token;
    [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.server.updateEmail"
                                        service:nil
                                           body:body
                                  authenticated:YES
                                     completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)value;
      (void)response;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (error) [self showError:error.localizedDescription];
        [self reloadSectionData];
      });
    }];
  }];
}

- (void)showEmailConfirmationMenu {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  [alert addAction:[UIAlertAction actionWithTitle:@"Send confirmation email" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    (void)action;
    [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.server.requestEmailConfirmation" service:nil body:@{} authenticated:YES completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
      (void)value;
      (void)response;
      dispatch_async(dispatch_get_main_queue(), ^{
        if (error) [self showError:error.localizedDescription];
      });
    }];
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Confirm with token" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    (void)action;
    [self promptForTextWithTitle:@"Email address" placeholder:@"email@example.com" secure:NO completion:^(NSString *email) {
      [self promptForTextWithTitle:@"Confirmation token" placeholder:@"Token" secure:NO completion:^(NSString *token) {
        [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.server.confirmEmail" service:nil body:@{@"email": email ?: @"", @"token": token ?: @""} authenticated:YES completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
          (void)value;
          (void)response;
          dispatch_async(dispatch_get_main_queue(), ^{
            if (error) [self showError:error.localizedDescription];
            [self reloadSectionData];
          });
        }];
      }];
    }];
  }]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)requestPasswordReset:(NSString *)email {
  NSString *safe = [email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (safe.length == 0) return;
  [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.server.requestPasswordReset"
                                      service:nil
                                         body:@{@"email": safe}
                                authenticated:NO
                                   completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
    (void)value;
    (void)response;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self showError:error.localizedDescription ?: @"Password reset email sent."];
    });
  }];
}

- (void)promptForPasswordResetConfirmation {
  [self promptForTextWithTitle:@"Reset token" placeholder:@"Token" secure:NO completion:^(NSString *token) {
    [self promptForTextWithTitle:@"New password" placeholder:@"Password" secure:YES completion:^(NSString *password) {
      [[NFBAtprotoSession sharedSession] xrpcPOST:@"com.atproto.server.resetPassword"
                                          service:nil
                                             body:@{@"token": token ?: @"", @"password": password ?: @""}
                                    authenticated:NO
                                       completion:^(id value, NSHTTPURLResponse *response, NSError *error) {
        (void)value;
        (void)response;
        dispatch_async(dispatch_get_main_queue(), ^{
          [self showError:error.localizedDescription ?: @"Password reset."];
        });
      }];
    }];
  }];
}

- (void)showMutedWordsMenu {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Muted words" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  [alert addAction:[UIAlertAction actionWithTitle:@"Add muted word" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    (void)action;
    [self promptForTextWithTitle:@"Add muted word" placeholder:@"Word, phrase, or tag" secure:NO completion:^(NSString *word) {
      [self addMutedWord:word];
    }];
  }]];
  NSArray *muted = [self mutedWords];
  for (NSDictionary *item in muted) {
    NSString *value = [item[@"value"] isKindOfClass:NSString.class] ? item[@"value"] : @"";
    if (value.length == 0) continue;
    [alert addAction:[UIAlertAction actionWithTitle:[@"Remove " stringByAppendingString:value] style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
      (void)action;
      [self removeMutedWord:item];
    }]];
  }
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)addMutedWord:(NSString *)word {
  NSString *safe = [word stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (safe.length == 0) return;
  NSMutableDictionary *pref = [[self preferenceForType:@"app.bsky.actor.defs#mutedWordsPref" matching:nil] mutableCopy] ?: [@{@"$type": @"app.bsky.actor.defs#mutedWordsPref", @"items": @[]} mutableCopy];
  NSArray *existingItems = [pref[@"items"] isKindOfClass:NSArray.class] ? pref[@"items"] : @[];
  NSMutableArray *items = [existingItems mutableCopy];
  [items addObject:@{@"value": safe, @"targets": @[@"content", @"tag"], @"actorTarget": @"all"}];
  pref[@"items"] = items;
  [self replacePreference:pref type:@"app.bsky.actor.defs#mutedWordsPref" matching:nil];
  [self savePreferencesAndRebuild];
}

- (void)removeMutedWord:(NSDictionary *)word {
  NSMutableDictionary *pref = [[self preferenceForType:@"app.bsky.actor.defs#mutedWordsPref" matching:nil] mutableCopy] ?: [@{@"$type": @"app.bsky.actor.defs#mutedWordsPref", @"items": @[]} mutableCopy];
  NSArray *existingItems = [pref[@"items"] isKindOfClass:NSArray.class] ? pref[@"items"] : @[];
  NSMutableArray *items = [existingItems mutableCopy];
  [items removeObject:word];
  pref[@"items"] = items;
  [self replacePreference:pref type:@"app.bsky.actor.defs#mutedWordsPref" matching:nil];
  [self savePreferencesAndRebuild];
}

- (void)showInterestsMenu {
  [self promptForTextWithTitle:@"Interests" placeholder:@"Comma separated topics" secure:NO completion:^(NSString *text) {
    NSArray *parts = [text componentsSeparatedByString:@","];
    NSMutableArray *tags = [NSMutableArray array];
    for (NSString *part in parts) {
      NSString *tag = [[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
      if (tag.length > 0) [tags addObject:[tag stringByReplacingOccurrencesOfString:@"#" withString:@""]];
    }
    NSMutableDictionary *pref = [@{@"$type": @"app.bsky.actor.defs#interestsPref", @"tags": tags} mutableCopy];
    [self replacePreference:pref type:@"app.bsky.actor.defs#interestsPref" matching:nil];
    [self savePreferencesAndRebuild];
  }];
}

- (void)promptForTextWithTitle:(NSString *)title placeholder:(NSString *)placeholder secure:(BOOL)secure completion:(void (^)(NSString *value))completion {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.placeholder = placeholder;
    textField.secureTextEntry = secure;
    textField.textColor = UIColor.labelColor;
  }];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    (void)action;
    if (completion) completion(alert.textFields.firstObject.text ?: @"");
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)promptForNumberWithTitle:(NSString *)title current:(NSInteger)current completion:(void (^)(NSInteger value))completion {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleAlert];
  [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
    textField.keyboardType = UIKeyboardTypeNumberPad;
    textField.text = [NSString stringWithFormat:@"%ld", (long)current];
  }];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    (void)action;
    NSInteger value = [alert.textFields.firstObject.text integerValue];
    if (completion) completion(MAX(0, MIN(1000, value)));
  }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)showChoiceWithTitle:(NSString *)title options:(NSArray<NSDictionary *> *)options current:(NSString *)current completion:(void (^)(NSString *value))completion {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  for (NSDictionary *option in options) {
    NSString *value = option[@"value"];
    NSString *label = option[@"label"];
    NSString *display = [value isEqualToString:current] ? [label stringByAppendingString:@" ✓"] : label;
    [alert addAction:[UIAlertAction actionWithTitle:display style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
      (void)action;
      if (completion) completion(value);
    }]];
  }
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)showError:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message ?: @"" preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)maskedEmail:(NSString *)email {
  if (email.length == 0) return @"Not exposed by session";
  NSArray *parts = [email componentsSeparatedByString:@"@"];
  if (parts.count != 2) return @"Available in session";
  NSString *name = parts.firstObject;
  NSString *visible = [name substringToIndex:MIN((NSUInteger)2, name.length)];
  return [NSString stringWithFormat:@"%@%@%@", visible, name.length > 2 ? @"***@" : @"*@", parts.lastObject];
}

- (NSString *)booleanLabel:(id)value {
  if (![value respondsToSelector:@selector(boolValue)]) return @"Unknown";
  return [value boolValue] ? @"On" : @"Off";
}

- (NSString *)statusLabelForAccount:(NSDictionary *)account {
  NSString *status = [account[@"status"] isKindOfClass:NSString.class] ? account[@"status"] : @"";
  if (status.length > 0) return status;
  if ([account[@"active"] respondsToSelector:@selector(boolValue)] && ![account[@"active"] boolValue]) return @"Inactive";
  return @"Active";
}

- (NSString *)normalizedChatAllowIncoming:(NSString *)value {
  if ([value isEqualToString:@"following"] || [value isEqualToString:@"none"]) return value;
  return @"all";
}

- (NSArray<NSDictionary *> *)replyOptions {
  return @[
    @{@"value": @"everyone", @"label": @"Everyone"},
    @{@"value": @"following", @"label": @"People you follow"},
    @{@"value": @"followers", @"label": @"Your followers"},
    @{@"value": @"mentioned", @"label": @"People you mention"},
    @{@"value": @"nobody", @"label": @"No one"}
  ];
}

- (NSArray<NSDictionary *> *)quoteOptions {
  return @[@{@"value": @"enabled", @"label": @"On"}, @{@"value": @"disabled", @"label": @"Off"}];
}

- (NSArray<NSDictionary *> *)chatOptions {
  return @[
    @{@"value": @"all", @"label": @"Everyone"},
    @{@"value": @"following", @"label": @"People you follow"},
    @{@"value": @"none", @"label": @"No one"}
  ];
}

- (NSArray<NSDictionary *> *)threadSortOptions {
  return @[
    @{@"value": @"hotness", @"label": @"Most relevant"},
    @{@"value": @"oldest", @"label": @"Oldest first"},
    @{@"value": @"newest", @"label": @"Newest first"},
    @{@"value": @"most-likes", @"label": @"Most liked first"}
  ];
}

- (NSArray<NSDictionary *> *)labelVisibilityOptions {
  return @[
    @{@"value": @"ignore", @"label": @"Off"},
    @{@"value": @"warn", @"label": @"Warn"},
    @{@"value": @"hide", @"label": @"Hide"}
  ];
}

- (NSArray<NSDictionary *> *)notificationIncludeOptionsForChat:(BOOL)chat {
  return chat ? @[
    @{@"value": @"all", @"label": @"Anyone"},
    @{@"value": @"accepted", @"label": @"Accepted only"}
  ] : @[
    @{@"value": @"all", @"label": @"Anyone"},
    @{@"value": @"follows", @"label": @"People you follow"}
  ];
}

- (NSArray<NSDictionary *> *)notificationDefinitions {
  return @[
    @{@"key": @"chat", @"title": @"Messages", @"description": @"Direct message notifications."},
    @{@"key": @"mention", @"title": @"Mentions", @"description": @"Posts that mention you."},
    @{@"key": @"reply", @"title": @"Replies", @"description": @"Replies to your posts and threads."},
    @{@"key": @"follow", @"title": @"New followers", @"description": @"People who follow you."},
    @{@"key": @"like", @"title": @"Likes", @"description": @"Likes on your posts."},
    @{@"key": @"repost", @"title": @"Reposts", @"description": @"Reposts of your posts."},
    @{@"key": @"quote", @"title": @"Quotes", @"description": @"Quote posts of your posts."},
    @{@"key": @"verified", @"title": @"Verified interactions", @"description": @"Activity from verified accounts."},
    @{@"key": @"unverified", @"title": @"Unverified interactions", @"description": @"Activity from accounts without verification."}
  ];
}

- (NSArray<NSDictionary *> *)contentLabelConfigs {
  return @[
    @{@"label": @"porn", @"title": @"Porn", @"default": @"hide"},
    @{@"label": @"sexual", @"title": @"Sexual", @"default": @"warn"},
    @{@"label": @"nudity", @"title": @"Nudity", @"default": @"warn"},
    @{@"label": @"sexual-figurative", @"title": @"Suggestive", @"default": @"ignore", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"graphic-media", @"title": @"Graphic media", @"default": @"warn"},
    @{@"label": @"self-harm", @"title": @"Self-harm", @"default": @"warn", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"sensitive", @"title": @"Sensitive", @"default": @"warn", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"violence", @"title": @"Violence", @"default": @"warn"},
    @{@"label": @"graphic-violence", @"title": @"Graphic violence", @"default": @"warn"},
    @{@"label": @"politics", @"title": @"Politics", @"default": @"warn"},
    @{@"label": @"conspiracy", @"title": @"Conspiracy theories", @"default": @"warn"},
    @{@"label": @"extremist", @"title": @"Extremist", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"intolerant", @"title": @"Intolerance", @"default": @"warn", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"threat", @"title": @"Threats", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"rude", @"title": @"Rude", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"illicit", @"title": @"Illicit", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"security", @"title": @"Security Concerns", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"unsafe-link", @"title": @"Unsafe link", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"impersonation", @"title": @"Impersonation", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"misinformation", @"title": @"Misinformation", @"default": @"warn", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"scam", @"title": @"Scam", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"engagement-farming", @"title": @"Engagement Farming", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"spam", @"title": @"Spam", @"default": @"hide", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"rumor", @"title": @"Unconfirmed", @"default": @"warn", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"misleading", @"title": @"Misleading", @"default": @"warn", @"labelerDid": NFBModerationServiceDID},
    @{@"label": @"inauthentic", @"title": @"Inauthentic Account", @"default": @"hide", @"labelerDid": NFBModerationServiceDID}
  ];
}

- (NSDictionary *)contentLabelConfigForLabel:(NSString *)label {
  for (NSDictionary *config in [self contentLabelConfigs]) {
    if ([config[@"label"] isEqualToString:label]) return config;
  }
  return @{@"label": label ?: @"", @"title": label ?: @"", @"default": @"warn"};
}

- (NSString *)contentLabelVisibilityForConfig:(NSDictionary *)config {
  NSString *label = config[@"label"];
  NSString *labelerDid = [config[@"labelerDid"] isKindOfClass:NSString.class] ? config[@"labelerDid"] : @"";
  NSDictionary *preference = [self preferenceForType:@"app.bsky.actor.defs#contentLabelPref" matching:^BOOL(NSDictionary *candidate) {
    NSString *candidateLabel = [candidate[@"label"] isKindOfClass:NSString.class] ? candidate[@"label"] : @"";
    NSString *candidateLabeler = [candidate[@"labelerDid"] isKindOfClass:NSString.class] ? candidate[@"labelerDid"] : @"";
    return [candidateLabel isEqualToString:label] && [candidateLabeler isEqualToString:labelerDid];
  }];
  NSString *visibility = [preference[@"visibility"] isKindOfClass:NSString.class] ? preference[@"visibility"] : config[@"default"];
  if ([visibility isEqualToString:@"show"]) return @"ignore";
  if ([visibility isEqualToString:@"ignore"] || [visibility isEqualToString:@"warn"] || [visibility isEqualToString:@"hide"]) return visibility;
  return @"warn";
}

- (NSString *)labelForReplySetting:(NSString *)setting {
  for (NSDictionary *option in [self replyOptions]) if ([option[@"value"] isEqualToString:setting]) return option[@"label"];
  return @"Custom";
}

- (NSString *)labelForQuoteSetting:(NSString *)setting {
  return [setting isEqualToString:@"disabled"] ? @"Off" : ([setting isEqualToString:@"custom"] ? @"Custom" : @"On");
}

- (NSString *)labelForChatAllowIncoming:(NSString *)setting {
  for (NSDictionary *option in [self chatOptions]) if ([option[@"value"] isEqualToString:setting]) return option[@"label"];
  return @"Everyone";
}

- (NSString *)labelForThreadSort:(NSString *)sort {
  for (NSDictionary *option in [self threadSortOptions]) if ([option[@"value"] isEqualToString:sort]) return option[@"label"];
  return @"Most relevant";
}

- (NSString *)labelForContentVisibility:(NSString *)visibility {
  if ([visibility isEqualToString:@"hide"]) return @"Hide";
  if ([visibility isEqualToString:@"ignore"]) return @"Off";
  return @"Warn";
}

- (NSString *)labelForNotificationInclude:(NSString *)include chat:(BOOL)chat {
  if (chat && [include isEqualToString:@"accepted"]) return @"Accepted only";
  if ([include isEqualToString:@"follows"]) return @"People you follow";
  return @"Anyone";
}

@end

@interface NFBSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *settings;

@end

@implementation NFBSettingsViewController

+ (UIViewController *)notificationSettingsViewController {
  return [[NFBSettingsDetailViewController alloc] initWithSectionID:@"notifications" title:@"Notifications"];
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.titleView = NFBTitleView(@"Settings", nil);

  UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  closeButton.frame = CGRectMake(0.0, 0.0, 34.0, 34.0);
  [closeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  closeButton.tintColor = NFBColorText();
  [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:closeButton];

  [self buildSettingsList];
  [self buildTable];
  [self refreshTheme];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildSettingsList {
  self.settings = @[
    @{@"type": @"button", @"title": @"Your account", @"subtitle": @"See account information and supported account settings.", @"action": @"section_account", @"section": @"account"},
    @{@"type": @"button", @"title": @"Security and account access", @"subtitle": @"Review OAuth access, email state, and account status.", @"action": @"section_security", @"section": @"security"},
    @{@"type": @"button", @"title": @"Privacy and safety", @"subtitle": @"Control replies, quotes, messages, and muted words.", @"action": @"section_privacy", @"section": @"privacy"},
    @{@"type": @"button", @"title": @"Content you see", @"subtitle": @"Tune home feed, reply sorting, labels, and interests.", @"action": @"section_content", @"section": @"content"},
    @{@"type": @"button", @"title": @"Notifications", @"subtitle": @"Choose which Bluesky alerts appear in-app or as pushes.", @"action": @"section_notifications", @"section": @"notifications"},
    @{@"type": @"button", @"title": @"Accessibility, display, and languages", @"subtitle": @"Adjust local Not Twitter display, colors, and app icon.", @"action": @"section_display", @"section": @"display"}
  ];
}

- (void)buildTable {
  self.view.backgroundColor = NFBColorBackground();
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.showsVerticalScrollIndicator = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 60.0;
  [self.tableView registerClass:NFBSettingsRowCell.class forCellReuseIdentifier:@"settings"];
  [self.view addSubview:self.tableView];
  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];
}

- (void)refreshTheme {
  self.view.backgroundColor = NFBColorBackground();
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.navigationItem.leftBarButtonItem.customView.tintColor = NFBColorText();
  if (self.navigationController) NFBApplyNavigationAppearance(self.navigationController);
  [self.tableView reloadData];
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  [self refreshTheme];
}

- (void)closeTapped {
  [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  (void)tableView;
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return (NSInteger)self.settings.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NFBSettingsRowCell *cell = [tableView dequeueReusableCellWithIdentifier:@"settings" forIndexPath:indexPath];
  [cell configureWithItem:self.settings[(NSUInteger)indexPath.row]
                      row:indexPath.row
                   target:self
                   action:@selector(toggleChanged:)];
  return cell;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  UIView *header = [[UIView alloc] init];
  header.backgroundColor = NFBColorBackground();
  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = @"Manage your Bluesky account and Not Twitter app preferences.";
  label.numberOfLines = 0;
  label.font = NFBFont(13.0, NFBFontWeightRegular);
  label.textColor = NFBColorSecondaryText();
  [header addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
    [label.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
    [label.topAnchor constraintEqualToAnchor:header.topAnchor constant:8.0],
    [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8.0]
  ]];
  return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return UITableViewAutomaticDimension;
}

- (CGFloat)tableView:(UITableView *)tableView estimatedHeightForHeaderInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return 58.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return [[UIView alloc] initWithFrame:CGRectZero];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return 0.01;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  NSDictionary *item = self.settings[(NSUInteger)indexPath.row];
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"";
  if (![type isEqualToString:@"button"]) return;
  NSString *action = [item[@"action"] isKindOfClass:NSString.class] ? item[@"action"] : @"";
  if ([action hasPrefix:@"section_"]) {
    NSString *sectionID = [item[@"section"] isKindOfClass:NSString.class] ? item[@"section"] : @"display";
    NFBSettingsDetailViewController *detail = [[NFBSettingsDetailViewController alloc] initWithSectionID:sectionID title:item[@"title"] ?: @"Settings"];
    [self.navigationController pushViewController:detail animated:YES];
  } else if ([action isEqualToString:@"showDisplaySettings"]) {
    [self showDisplaySettings];
  } else if ([action isEqualToString:@"showAppIconSettings"]) {
    [self showAppIconSettings];
  }
}

- (void)toggleChanged:(UISwitch *)sender {
  NSInteger row = sender.tag;
  if (row < 0 || row >= (NSInteger)self.settings.count) return;
  NSDictionary *item = self.settings[(NSUInteger)row];
  NSString *key = [item[@"key"] isKindOfClass:NSString.class] ? item[@"key"] : @"";
  if (key.length == 0) return;
  [NSUserDefaults.standardUserDefaults setBool:sender.isOn forKey:key];
  [NSUserDefaults.standardUserDefaults synchronize];
}

- (void)showDisplaySettings {
  NFBDisplaySettingsViewController *display = [[NFBDisplaySettingsViewController alloc] init];
  [self.navigationController pushViewController:display animated:YES];
}

- (void)showAppIconSettings {
  NFBAppIconSettingsViewController *appIcon = [[NFBAppIconSettingsViewController alloc] init];
  [self.navigationController pushViewController:appIcon animated:YES];
}

@end
