#import "NFBSearchTypeaheadViewController.h"

#import "NFBAtprotoClient.h"
#import "NFBTheme.h"

static NSString * const NFBSearchRecentDefaultsKey = @"NFBSearchRecentSearches";
static NSUInteger const NFBSearchRecentLimit = 20;
static NSTimeInterval const NFBSearchTypeaheadDelay = 0.25;

@protocol NFBSearchRecentCellDelegate <NSObject>
- (void)searchRecentCellDidTapRemoveItem:(NSDictionary *)item;
@end

static NSString *NFBSearchTrimmedString(NSString *value) {
  return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

@interface NFBSearchOptionCell : UITableViewCell
@property (nonatomic, weak) id<NFBSearchRecentCellDelegate> delegate;
@property (nonatomic, strong) NSDictionary *representedItem;
- (void)configureWithTitle:(NSString *)title iconName:(NSString *)iconName item:(NSDictionary *)item removeVisible:(BOOL)removeVisible;
@end

@interface NFBSearchOptionCell ()
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *removeButton;
@end

@implementation NFBSearchOptionCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.representedItem = nil;
  self.delegate = nil;
  self.removeButton.hidden = YES;
  [self applyTheme];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.iconView = [[UIImageView alloc] init];
  self.iconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.iconView.contentMode = UIViewContentModeScaleAspectFit;

  self.titleLabel = [[UILabel alloc] init];
  self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.titleLabel.numberOfLines = 1;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.removeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.removeButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.removeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  self.removeButton.contentEdgeInsets = UIEdgeInsetsMake(11.0, 11.0, 11.0, 11.0);
  self.removeButton.accessibilityLabel = @"Remove";
  [self.removeButton addTarget:self action:@selector(removeTapped) forControlEvents:UIControlEventTouchUpInside];

  [self.contentView addSubview:self.iconView];
  [self.contentView addSubview:self.titleLabel];
  [self.contentView addSubview:self.removeButton];

  [NSLayoutConstraint activateConstraints:@[
    [self.iconView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:18.0],
    [self.iconView.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.iconView.widthAnchor constraintEqualToConstant:22.0],
    [self.iconView.heightAnchor constraintEqualToConstant:22.0],
    [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.iconView.trailingAnchor constant:18.0],
    [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.removeButton.leadingAnchor constant:-8.0],
    [self.titleLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.removeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
    [self.removeButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.removeButton.widthAnchor constraintEqualToConstant:44.0],
    [self.removeButton.heightAnchor constraintEqualToConstant:44.0],
    [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:50.0]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.iconView.tintColor = NFBColorSecondaryText();
  self.titleLabel.textColor = NFBColorText();
  self.removeButton.tintColor = NFBColorSecondaryText();
}

- (void)configureWithTitle:(NSString *)title iconName:(NSString *)iconName item:(NSDictionary *)item removeVisible:(BOOL)removeVisible {
  [self applyTheme];
  self.representedItem = item;
  self.titleLabel.text = title ?: @"";
  self.iconView.image = NFBTemplateIcon(iconName ?: @"nfb_search");
  self.removeButton.hidden = !removeVisible;
}

- (void)removeTapped {
  if ([self.delegate respondsToSelector:@selector(searchRecentCellDidTapRemoveItem:)]) {
    [self.delegate searchRecentCellDidTapRemoveItem:self.representedItem ?: @{}];
  }
}

@end

@interface NFBSearchProfileCell : UITableViewCell
@property (nonatomic, weak) id<NFBSearchRecentCellDelegate> delegate;
@property (nonatomic, strong) NSDictionary *representedItem;
- (void)configureWithProfile:(NSDictionary *)profile item:(NSDictionary *)item removeVisible:(BOOL)removeVisible;
@end

@interface NFBSearchProfileCell ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *followsYouLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong) UIButton *removeButton;
@property (nonatomic, copy) NSString *avatarURLString;
@end

@implementation NFBSearchProfileCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.delegate = nil;
  self.representedItem = nil;
  self.avatarURLString = nil;
  self.avatarView.image = [self.class placeholderAvatarImage];
  self.removeButton.hidden = YES;
  [self applyTheme];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.avatarView = [[UIImageView alloc] initWithImage:[self.class placeholderAvatarImage]];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = 24.0;

  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightBold);
  self.nameLabel.numberOfLines = 1;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  self.verifiedBadgeView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  self.verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
  self.verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
  [self.verifiedBadgeView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.verifiedBadgeView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.verifiedBadgeView]];
  nameRow.translatesAutoresizingMaskIntoConstraints = NO;
  nameRow.axis = UILayoutConstraintAxisHorizontal;
  nameRow.alignment = UIStackViewAlignmentCenter;
  nameRow.distribution = UIStackViewDistributionFill;
  nameRow.spacing = 3.0;
  [nameRow setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [nameRow setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  self.handleLabel = [[UILabel alloc] init];
  self.handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.handleLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineMetaFontSize), NFBFontWeightRegular);
  self.handleLabel.numberOfLines = 1;
  self.handleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.followsYouLabel = [[UILabel alloc] init];
  self.followsYouLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.followsYouLabel.hidden = YES;
  NFBIPAApplyFollowsYouBadgeAppearance(self.followsYouLabel);

  UIStackView *handleRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.handleLabel, self.followsYouLabel]];
  handleRow.translatesAutoresizingMaskIntoConstraints = NO;
  handleRow.axis = UILayoutConstraintAxisHorizontal;
  handleRow.alignment = UIStackViewAlignmentCenter;
  handleRow.spacing = 6.0;

  self.bioLabel = [[UILabel alloc] init];
  self.bioLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.bioLabel.font = NFBFont(NFBIPAMetricValue(NFBIPAMetricTimelineBodyFontSize), NFBFontWeightRegular);
  self.bioLabel.numberOfLines = 2;
  self.bioLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, handleRow, self.bioLabel]];
  textStack.translatesAutoresizingMaskIntoConstraints = NO;
  textStack.axis = UILayoutConstraintAxisVertical;
  textStack.alignment = UIStackViewAlignmentFill;
  textStack.spacing = 1.0;

  self.removeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.removeButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.removeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  self.removeButton.contentEdgeInsets = UIEdgeInsetsMake(11.0, 11.0, 11.0, 11.0);
  self.removeButton.accessibilityLabel = @"Remove";
  [self.removeButton addTarget:self action:@selector(removeTapped) forControlEvents:UIControlEventTouchUpInside];

  [self.contentView addSubview:self.avatarView];
  [self.contentView addSubview:textStack];
  [self.contentView addSubview:self.removeButton];

  [NSLayoutConstraint activateConstraints:@[
    [self.avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:NFBIPAMetricValue(NFBIPAMetricTimelineHorizontalInset)],
    [self.avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11.0],
    [self.avatarView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricTimelineAvatarSize)],
    [self.avatarView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricTimelineAvatarSize)],
    [textStack.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:12.0],
    [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.removeButton.leadingAnchor constant:-8.0],
    [textStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:9.0],
    [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10.0],
    [handleRow.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
    [self.followsYouLabel.heightAnchor constraintEqualToConstant:18.0],
    [self.followsYouLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],
    [self.verifiedBadgeView.widthAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [self.verifiedBadgeView.heightAnchor constraintEqualToConstant:NFBIPAMetricValue(NFBIPAMetricVerifiedBadgeSize)],
    [self.removeButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-8.0],
    [self.removeButton.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.removeButton.widthAnchor constraintEqualToConstant:44.0],
    [self.removeButton.heightAnchor constraintEqualToConstant:44.0],
    [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:70.0]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.avatarView.backgroundColor = NFBColorElevatedBackground();
  self.nameLabel.textColor = NFBColorText();
  self.handleLabel.textColor = NFBColorSecondaryText();
  NFBIPAApplyFollowsYouBadgeAppearance(self.followsYouLabel);
  self.bioLabel.textColor = NFBColorText();
  self.removeButton.tintColor = NFBColorSecondaryText();
}

- (void)configureWithProfile:(NSDictionary *)profile item:(NSDictionary *)item removeVisible:(BOOL)removeVisible {
  [self applyTheme];
  self.representedItem = item;
  self.nameLabel.text = [NFBAtprotoClient displayNameForProfile:profile];
  BOOL verified = [NFBAtprotoClient isProfileVerified:profile];
  if (!verified && [profile[@"verified"] respondsToSelector:@selector(boolValue)]) verified = [profile[@"verified"] boolValue];
  self.verifiedBadgeView.hidden = !verified;
  NSString *handle = [NFBAtprotoClient handleForProfile:profile];
  self.handleLabel.text = [handle hasPrefix:@"@"] ? handle : [@"@" stringByAppendingString:handle ?: @""];
  self.followsYouLabel.hidden = !NFBIPAProfileFollowsViewer(profile);
  NSString *bio = [profile[@"description"] isKindOfClass:NSString.class] ? profile[@"description"] : @"";
  self.bioLabel.attributedText = NFBTweetBodyAttributedString(bio, self.bioLabel.font);
  self.bioLabel.hidden = bio.length == 0;
  self.removeButton.hidden = !removeVisible;
  [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:profile]];
}

- (void)loadAvatarURL:(NSString *)urlString {
  self.avatarURLString = urlString;
  if (urlString.length == 0) {
    self.avatarView.image = [self.class placeholderAvatarImage];
    return;
  }

  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    self.avatarView.image = cached;
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.avatarURLString isEqualToString:urlString]) self.avatarView.image = image;
    });
  }] resume];
}

- (void)removeTapped {
  if ([self.delegate respondsToSelector:@selector(searchRecentCellDidTapRemoveItem:)]) {
    [self.delegate searchRecentCellDidTapRemoveItem:self.representedItem ?: @{}];
  }
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 80;
  });
  return cache;
}

+ (UIImage *)placeholderAvatarImage {
  static UIImage *image = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    image = NFBDefaultAvatarImage();
  });
  return image;
}

@end

@interface NFBSearchEmptyCell : UITableViewCell
- (void)configureWithText:(NSString *)text;
@end

@interface NFBSearchEmptyCell ()
@property (nonatomic, strong) UILabel *messageLabel;
@end

@implementation NFBSearchEmptyCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.messageLabel = [[UILabel alloc] init];
  self.messageLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.messageLabel.textAlignment = NSTextAlignmentCenter;
  self.messageLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.messageLabel.numberOfLines = 0;
  [self.contentView addSubview:self.messageLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.messageLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:32.0],
    [self.messageLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-32.0],
    [self.messageLabel.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
    [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:132.0]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.messageLabel.textColor = NFBColorSecondaryText();
}

- (void)configureWithText:(NSString *)text {
  [self applyTheme];
  self.messageLabel.text = text ?: @"";
}

@end

@interface NFBSearchTypeaheadViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, NFBSearchRecentCellDelegate>
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *searchContainer;
@property (nonatomic, strong) UIImageView *searchIconView;
@property (nonatomic, strong) UITextField *searchField;
@property (nonatomic, strong) UIButton *clearButton;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, copy) NSString *query;
@property (nonatomic, copy) NSArray<NSDictionary *> *recentItems;
@property (nonatomic, copy) NSArray<NSDictionary *> *suggestedProfiles;
@property (nonatomic, assign) BOOL loadingSuggestions;
@property (nonatomic, copy) NSString *suggestionErrorMessage;
@property (nonatomic, assign) NSUInteger suggestionGeneration;
@property (nonatomic, strong) NSMutableSet<NSString *> *hydratingRecentActors;
@end

@implementation NFBSearchTypeaheadViewController

- (instancetype)initWithInitialQuery:(NSString *)query {
  self = [super initWithNibName:nil bundle:nil];
	if (self) {
	    _query = [NFBSearchTrimmedString(query) copy];
	    _recentItems = [self.class recentSearches];
	    _suggestedProfiles = @[];
	    _hydratingRecentActors = [NSMutableSet set];
	    self.modalPresentationStyle = UIModalPresentationFullScreen;
	  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  [self buildTopBar];
  [self buildTableView];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
  [self updateForQueryChangeReloading:YES];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self.searchField becomeFirstResponder];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];
}

- (void)buildTopBar {
  self.topBar = [[UIView alloc] init];
  self.topBar.translatesAutoresizingMaskIntoConstraints = NO;

  self.searchContainer = [[UIView alloc] init];
  self.searchContainer.translatesAutoresizingMaskIntoConstraints = NO;
  NFBIPAApplySearchContainerAppearance(self.searchContainer);

  self.searchIconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_search")];
  self.searchIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchIconView.contentMode = UIViewContentModeScaleAspectFit;

  self.searchField = [[UITextField alloc] init];
  self.searchField.translatesAutoresizingMaskIntoConstraints = NO;
  self.searchField.delegate = self;
  self.searchField.text = self.query;
  NFBIPAApplySearchTextFieldAppearance(self.searchField, @"Search Twitter");
  self.searchField.returnKeyType = UIReturnKeySearch;
  self.searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  self.searchField.autocorrectionType = UITextAutocorrectionTypeNo;
  self.searchField.spellCheckingType = UITextSpellCheckingTypeNo;
  self.searchField.clearButtonMode = UITextFieldViewModeNever;
  [self.searchField addTarget:self action:@selector(searchFieldChanged:) forControlEvents:UIControlEventEditingChanged];

  self.clearButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.clearButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.clearButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
  self.clearButton.contentEdgeInsets = UIEdgeInsetsMake(9.0, 9.0, 9.0, 9.0);
  self.clearButton.accessibilityLabel = @"Clear text";
  [self.clearButton addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];

  self.cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
  [self.cancelButton setImage:NFBTemplateIcon(@"nfb_arrow_left") forState:UIControlStateNormal];
  self.cancelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
  self.cancelButton.contentEdgeInsets = UIEdgeInsetsMake(8.0, 0.0, 8.0, 16.0);
  self.cancelButton.accessibilityLabel = @"Back";
  [self.cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];

  UIView *bottomBorder = [[UIView alloc] init];
  bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;
  bottomBorder.tag = 43118;

  [self.view addSubview:self.topBar];
  [self.topBar addSubview:self.searchContainer];
  [self.searchContainer addSubview:self.searchIconView];
  [self.searchContainer addSubview:self.searchField];
  [self.searchContainer addSubview:self.clearButton];
  [self.topBar addSubview:self.cancelButton];
  [self.topBar addSubview:bottomBorder];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.topBar.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.topBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.topBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.topBar.heightAnchor constraintEqualToConstant:53.0],
    [self.cancelButton.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor constant:12.0],
    [self.cancelButton.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
    [self.cancelButton.widthAnchor constraintEqualToConstant:44.0],
    [self.cancelButton.heightAnchor constraintEqualToConstant:44.0],
    [self.searchContainer.leadingAnchor constraintEqualToAnchor:self.cancelButton.trailingAnchor constant:0.0],
    [self.searchContainer.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor constant:-16.0],
    [self.searchContainer.centerYAnchor constraintEqualToAnchor:self.topBar.centerYAnchor],
    [self.searchContainer.heightAnchor constraintEqualToConstant:36.0],
    [self.searchIconView.leadingAnchor constraintEqualToAnchor:self.searchContainer.leadingAnchor constant:13.0],
    [self.searchIconView.centerYAnchor constraintEqualToAnchor:self.searchContainer.centerYAnchor],
    [self.searchIconView.widthAnchor constraintEqualToConstant:18.0],
    [self.searchIconView.heightAnchor constraintEqualToConstant:18.0],
    [self.searchField.leadingAnchor constraintEqualToAnchor:self.searchIconView.trailingAnchor constant:10.0],
    [self.searchField.trailingAnchor constraintEqualToAnchor:self.clearButton.leadingAnchor constant:-4.0],
    [self.searchField.topAnchor constraintEqualToAnchor:self.searchContainer.topAnchor],
    [self.searchField.bottomAnchor constraintEqualToAnchor:self.searchContainer.bottomAnchor],
    [self.clearButton.trailingAnchor constraintEqualToAnchor:self.searchContainer.trailingAnchor constant:-4.0],
    [self.clearButton.centerYAnchor constraintEqualToAnchor:self.searchContainer.centerYAnchor],
    [self.clearButton.widthAnchor constraintEqualToConstant:32.0],
    [self.clearButton.heightAnchor constraintEqualToConstant:32.0],
    [bottomBorder.leadingAnchor constraintEqualToAnchor:self.topBar.leadingAnchor],
    [bottomBorder.trailingAnchor constraintEqualToAnchor:self.topBar.trailingAnchor],
    [bottomBorder.bottomAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
    [bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  [self applyTheme];
}

- (void)buildTableView {
  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 64.0;
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
  self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  [self.tableView registerClass:NFBSearchOptionCell.class forCellReuseIdentifier:@"option"];
  [self.tableView registerClass:NFBSearchProfileCell.class forCellReuseIdentifier:@"profile"];
  [self.tableView registerClass:NFBSearchEmptyCell.class forCellReuseIdentifier:@"empty"];

  [self.view addSubview:self.tableView];
  [NSLayoutConstraint activateConstraints:@[
    [self.tableView.topAnchor constraintEqualToAnchor:self.topBar.bottomAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  self.view.backgroundColor = NFBColorBackground();
  self.topBar.backgroundColor = NFBColorBackground();
  NFBIPAApplySearchContainerAppearance(self.searchContainer);
  self.searchIconView.tintColor = NFBColorSecondaryText();
  NFBIPAApplySearchTextFieldAppearance(self.searchField, @"Search Twitter");
  self.clearButton.tintColor = NFBColorSecondaryText();
  self.cancelButton.tintColor = NFBColorText();
  NFBIPAApplyTableViewAppearance(self.tableView);
  for (UIView *subview in self.topBar.subviews) {
    if (subview.tag == 43118) NFBIPAApplyTableSeparatorAppearance(subview);
  }
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  [self applyTheme];
  [self.tableView reloadData];
}

- (void)searchFieldChanged:(UITextField *)field {
  self.query = NFBSearchTrimmedString(field.text ?: @"");
  [self updateForQueryChangeReloading:YES];
}

- (void)updateForQueryChangeReloading:(BOOL)reload {
  self.clearButton.hidden = self.searchField.text.length == 0;
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(fetchSuggestions) object:nil];

  if (self.query.length == 0) {
    self.recentItems = [self.class recentSearches];
    self.suggestedProfiles = @[];
    self.loadingSuggestions = NO;
    self.suggestionErrorMessage = @"";
    if (reload) [self.tableView reloadData];
    return;
  }

  self.loadingSuggestions = YES;
  self.suggestionErrorMessage = @"";
  if (reload) [self.tableView reloadData];
  [self performSelector:@selector(fetchSuggestions) withObject:nil afterDelay:NFBSearchTypeaheadDelay];
}

- (void)fetchSuggestions {
  NSString *query = [self.query copy];
  if (query.length == 0) return;
  NSUInteger generation = ++self.suggestionGeneration;
  [[NFBAtprotoClient sharedClient] searchActors:query limit:5 completion:^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    (void)cursor;
    dispatch_async(dispatch_get_main_queue(), ^{
      if (generation != self.suggestionGeneration || ![query isEqualToString:self.query]) return;
      self.loadingSuggestions = NO;
      if (error) {
        self.suggestionErrorMessage = error.localizedDescription ?: @"Something went wrong. Try searching again.";
        self.suggestedProfiles = @[];
      } else {
        self.suggestionErrorMessage = @"";
        self.suggestedProfiles = items ?: @[];
      }
      [self.tableView reloadData];
    });
  }];
}

- (void)clearTapped {
  self.searchField.text = @"";
  self.query = @"";
  [self updateForQueryChangeReloading:YES];
  [self.searchField becomeFirstResponder];
}

- (void)cancelTapped {
  [self.searchField resignFirstResponder];
  [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
  (void)textField;
  [self performSearchWithQuery:self.query];
  return NO;
}

- (NSString *)profileActorForCurrentQuery {
  NSString *trimmed = NFBSearchTrimmedString(self.query);
  if (trimmed.length == 0) return @"";
  if ([trimmed hasPrefix:@"#"]) return @"";
  if ([trimmed rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound) return @"";

  NSString *actor = trimmed;
  if ([actor hasPrefix:@"@"]) actor = [actor substringFromIndex:1];
  if ([actor hasPrefix:@"did:"]) return actor;
  if ([actor rangeOfString:@"."].location == NSNotFound) actor = [actor stringByAppendingString:@".bsky.social"];
  return actor;
}

- (NSString *)profileActorDisplayLabel {
  NSString *trimmed = NFBSearchTrimmedString(self.query);
  if (trimmed.length == 0) return @"";
  if ([trimmed hasPrefix:@"@"]) return trimmed;
  if ([trimmed hasPrefix:@"did:"]) return trimmed;
  return [@"@" stringByAppendingString:trimmed];
}

- (void)performSearchWithQuery:(NSString *)query {
  NSString *trimmed = NFBSearchTrimmedString(query);
  if (trimmed.length == 0) return;
  [self.class addRecentSearchQuery:trimmed];
  [self.searchField resignFirstResponder];
  if ([self.delegate respondsToSelector:@selector(searchTypeaheadViewController:didSelectSearchQuery:)]) {
    [self.delegate searchTypeaheadViewController:self didSelectSearchQuery:trimmed];
  } else {
    [self dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)performProfileSelection:(NSDictionary *)profile {
  NSString *actor = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  if (actor.length == 0) actor = [profile[@"handle"] isKindOfClass:NSString.class] ? profile[@"handle"] : @"";
  if (actor.length == 0) return;
  [self.class addRecentSearchProfile:profile];
  [self.searchField resignFirstResponder];
  if ([self.delegate respondsToSelector:@selector(searchTypeaheadViewController:didSelectActor:)]) {
    [self.delegate searchTypeaheadViewController:self didSelectActor:actor];
  } else {
    [self dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)performProfileActorSelection {
  NSString *actor = [self profileActorForCurrentQuery];
  if (actor.length == 0) return;
  NSString *handle = [actor hasPrefix:@"did:"] ? [self profileActorDisplayLabel] : actor;
  [self.class addRecentSearchProfile:@{
    @"did": actor,
    @"handle": handle ?: @"",
    @"displayName": [self profileActorDisplayLabel] ?: handle ?: @"",
    @"avatar": @"",
    @"description": @"",
    @"verified": @NO,
    @"_nfbHydrated": @NO
  }];
  [self.searchField resignFirstResponder];
  if ([self.delegate respondsToSelector:@selector(searchTypeaheadViewController:didSelectActor:)]) {
    [self.delegate searchTypeaheadViewController:self didSelectActor:actor];
  } else {
    [self dismissViewControllerAnimated:YES completion:nil];
  }
}

#pragma mark - Recents

+ (NSArray<NSDictionary *> *)recentSearches {
  NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:NFBSearchRecentDefaultsKey];
  if (![stored isKindOfClass:NSArray.class]) return @[];
  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  for (NSDictionary *item in stored) {
    if (![item isKindOfClass:NSDictionary.class]) continue;
    NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"query";
    if ([type isEqualToString:@"user"]) {
      NSString *actor = [item[@"did"] isKindOfClass:NSString.class] ? item[@"did"] : @"";
      NSString *handle = [item[@"handle"] isKindOfClass:NSString.class] ? item[@"handle"] : @"";
      if (actor.length == 0 && handle.length == 0) continue;
      [items addObject:item];
    } else {
      NSString *query = [item[@"query"] isKindOfClass:NSString.class] ? item[@"query"] : @"";
      if (query.length == 0) continue;
      [items addObject:@{@"type": @"query", @"query": query}];
    }
  }
  return items;
}

+ (void)saveRecentSearches:(NSArray<NSDictionary *> *)items {
  [NSUserDefaults.standardUserDefaults setObject:items forKey:NFBSearchRecentDefaultsKey];
  [NSUserDefaults.standardUserDefaults synchronize];
}

+ (NSString *)recentKeyForItem:(NSDictionary *)item {
  NSString *type = [item[@"type"] isKindOfClass:NSString.class] ? item[@"type"] : @"query";
  if ([type isEqualToString:@"user"]) {
    NSString *actor = [item[@"did"] isKindOfClass:NSString.class] ? item[@"did"] : @"";
    if (actor.length == 0) actor = [item[@"handle"] isKindOfClass:NSString.class] ? item[@"handle"] : @"";
    return [[@"user:" stringByAppendingString:actor ?: @""] lowercaseString];
  }
  NSString *query = [item[@"query"] isKindOfClass:NSString.class] ? item[@"query"] : @"";
  return [[@"query:" stringByAppendingString:query ?: @""] lowercaseString];
}

+ (void)addRecentItem:(NSDictionary *)newItem {
  NSString *newKey = [self recentKeyForItem:newItem];
  if (newKey.length == 0) return;
  NSMutableArray<NSDictionary *> *items = [NSMutableArray arrayWithObject:newItem];
  for (NSDictionary *item in [self recentSearches]) {
    if ([[self recentKeyForItem:item] isEqualToString:newKey]) continue;
    [items addObject:item];
    if (items.count >= NFBSearchRecentLimit) break;
  }
  [self saveRecentSearches:items];
}

+ (void)addRecentSearchQuery:(NSString *)query {
  NSString *trimmed = NFBSearchTrimmedString(query);
  if (trimmed.length == 0) return;
  [self addRecentItem:@{@"type": @"query", @"query": trimmed}];
}

+ (void)addRecentSearchProfile:(NSDictionary *)profile {
  if (![profile isKindOfClass:NSDictionary.class]) return;
  NSString *actor = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
  NSString *handle = [NFBAtprotoClient canonicalHandleForProfile:profile];
  if (actor.length == 0 && handle.length == 0) return;
  NSString *displayName = [NFBAtprotoClient displayNameForProfile:profile];
  NSString *avatar = [NFBAtprotoClient avatarURLForProfile:profile];
  NSString *description = [profile[@"description"] isKindOfClass:NSString.class] ? profile[@"description"] : @"";
  NSMutableDictionary *item = [@{
    @"type": @"user",
    @"did": actor ?: @"",
    @"handle": handle ?: @"",
    @"displayName": displayName ?: @"",
    @"avatar": avatar ?: @"",
    @"description": description ?: @"",
    @"verified": @([NFBAtprotoClient isProfileVerified:profile]),
    @"_nfbHydrated": @YES
  } mutableCopy];
  [self addRecentItem:item];
}

+ (void)removeRecentItem:(NSDictionary *)itemToRemove {
  NSString *removeKey = [self recentKeyForItem:itemToRemove];
  if (removeKey.length == 0) return;
  NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
  for (NSDictionary *item in [self recentSearches]) {
    if ([[self recentKeyForItem:item] isEqualToString:removeKey]) continue;
    [items addObject:item];
  }
  [self saveRecentSearches:items];
}

+ (void)clearRecentSearches {
  [self saveRecentSearches:@[]];
}

- (void)searchRecentCellDidTapRemoveItem:(NSDictionary *)item {
  [self.class removeRecentItem:item];
  self.recentItems = [self.class recentSearches];
  [self.tableView reloadData];
}

- (void)hydrateRecentProfileIfNeeded:(NSDictionary *)item indexPath:(NSIndexPath *)indexPath {
  if (![item[@"type"] isEqualToString:@"user"]) return;
  NSString *actor = [item[@"did"] isKindOfClass:NSString.class] ? item[@"did"] : @"";
  if (actor.length == 0) actor = [item[@"handle"] isKindOfClass:NSString.class] ? item[@"handle"] : @"";
  if (actor.length == 0) return;

  BOOL hydrated = [item[@"_nfbHydrated"] respondsToSelector:@selector(boolValue)] && [item[@"_nfbHydrated"] boolValue];
  BOOL hasAvatar = [item[@"avatar"] isKindOfClass:NSString.class] && [item[@"avatar"] length] > 0;
  BOOL hasName = [item[@"displayName"] isKindOfClass:NSString.class] && [item[@"displayName"] length] > 0;
  BOOL hasVerifiedValue = [item[@"verified"] respondsToSelector:@selector(boolValue)] || [item[@"verification"] isKindOfClass:NSDictionary.class];
  if (hydrated && hasAvatar && hasName && hasVerifiedValue) return;

  NSString *key = actor.lowercaseString;
  if ([self.hydratingRecentActors containsObject:key]) return;
  [self.hydratingRecentActors addObject:key];

  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchProfileForActor:actor completion:^(NSDictionary *value, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      [strongSelf.hydratingRecentActors removeObject:key];
      if (error || ![value isKindOfClass:NSDictionary.class]) return;

      NSMutableDictionary *updated = [item mutableCopy];
      NSString *did = [value[@"did"] isKindOfClass:NSString.class] ? value[@"did"] : actor;
      NSString *handle = [NFBAtprotoClient canonicalHandleForProfile:value];
      NSString *displayName = [NFBAtprotoClient displayNameForProfile:value];
      NSString *avatar = [NFBAtprotoClient avatarURLForProfile:value];
      NSString *description = [value[@"description"] isKindOfClass:NSString.class] ? value[@"description"] : @"";
      updated[@"did"] = did ?: @"";
      updated[@"handle"] = handle ?: @"";
      updated[@"displayName"] = displayName ?: @"";
      updated[@"avatar"] = avatar ?: @"";
      updated[@"description"] = description ?: @"";
      updated[@"verified"] = @([NFBAtprotoClient isProfileVerified:value]);
      updated[@"_nfbHydrated"] = @YES;

      NSMutableArray<NSDictionary *> *items = [strongSelf.recentItems mutableCopy] ?: [NSMutableArray array];
      NSString *targetKey = [strongSelf.class recentKeyForItem:item];
      for (NSUInteger index = 0; index < items.count; index++) {
        if ([[strongSelf.class recentKeyForItem:items[index]] isEqualToString:targetKey]) {
          items[index] = [updated copy];
          break;
        }
      }
      strongSelf.recentItems = [items copy];
      [strongSelf.class saveRecentSearches:strongSelf.recentItems];
      if (indexPath.row < [strongSelf.tableView numberOfRowsInSection:indexPath.section]) {
        [strongSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
      } else {
        [strongSelf.tableView reloadData];
      }
    });
  }];
}

- (void)clearRecentSearchesTapped {
  [self.class clearRecentSearches];
  self.recentItems = @[];
  [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  (void)tableView;
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  if (self.query.length == 0) return MAX((NSInteger)self.recentItems.count, 1);

  NSInteger count = 1;
  if ([self profileActorForCurrentQuery].length > 0) count += 1;
  if (self.loadingSuggestions || self.suggestionErrorMessage.length > 0 || self.suggestedProfiles.count == 0) return count + 1;
  return count + (NSInteger)self.suggestedProfiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if (self.query.length == 0) {
    if (self.recentItems.count == 0) {
      NFBSearchEmptyCell *cell = [tableView dequeueReusableCellWithIdentifier:@"empty" forIndexPath:indexPath];
      [cell configureWithText:@"Try searching for people, topics, or keywords"];
      return cell;
    }
    NSDictionary *item = self.recentItems[(NSUInteger)indexPath.row];
    if ([item[@"type"] isEqualToString:@"user"]) {
      NFBSearchProfileCell *cell = [tableView dequeueReusableCellWithIdentifier:@"profile" forIndexPath:indexPath];
      cell.delegate = self;
      [cell configureWithProfile:item item:item removeVisible:YES];
      [self hydrateRecentProfileIfNeeded:item indexPath:indexPath];
      return cell;
    }
    NFBSearchOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    cell.delegate = self;
    [cell configureWithTitle:item[@"query"] ?: @"" iconName:@"nfb_search" item:item removeVisible:YES];
    return cell;
  }

  NSInteger row = indexPath.row;
  if (row == 0) {
    NFBSearchOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    [cell configureWithTitle:[NSString stringWithFormat:@"Search for “%@”", self.query] iconName:@"nfb_search" item:@{} removeVisible:NO];
    return cell;
  }

  BOOL hasProfileActor = [self profileActorForCurrentQuery].length > 0;
  if (hasProfileActor && row == 1) {
    NFBSearchOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    [cell configureWithTitle:[NSString stringWithFormat:@"Go to %@", [self profileActorDisplayLabel]] iconName:@"nfb_profile" item:@{} removeVisible:NO];
    return cell;
  }

  NSInteger userIndex = row - 1 - (hasProfileActor ? 1 : 0);
  if (self.loadingSuggestions) {
    NFBSearchOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    [cell configureWithTitle:@"Searching..." iconName:@"nfb_search" item:@{} removeVisible:NO];
    return cell;
  }
  if (self.suggestionErrorMessage.length > 0) {
    NFBSearchOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    [cell configureWithTitle:@"Something went wrong. Try searching again." iconName:@"nfb_search" item:@{} removeVisible:NO];
    return cell;
  }
  if (self.suggestedProfiles.count == 0) {
    NFBSearchOptionCell *cell = [tableView dequeueReusableCellWithIdentifier:@"option" forIndexPath:indexPath];
    [cell configureWithTitle:[NSString stringWithFormat:@"No people found for “%@”", self.query] iconName:@"nfb_profile" item:@{} removeVisible:NO];
    return cell;
  }

  NSDictionary *profile = self.suggestedProfiles[(NSUInteger)userIndex];
  NFBSearchProfileCell *cell = [tableView dequeueReusableCellWithIdentifier:@"profile" forIndexPath:indexPath];
  [cell configureWithProfile:profile item:@{} removeVisible:NO];
  return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return self.query.length == 0 && self.recentItems.count > 0 ? 50.0 : CGFLOAT_MIN;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  if (self.query.length > 0 || self.recentItems.count == 0) return nil;

  UIView *header = [[UIView alloc] init];
  header.backgroundColor = NFBColorBackground();

  UILabel *title = [[UILabel alloc] init];
  title.translatesAutoresizingMaskIntoConstraints = NO;
  title.text = @"Recent searches";
  title.textColor = NFBColorText();
  title.font = NFBFont(20.0, NFBFontWeightHeavy);

  UIButton *clear = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  clear.translatesAutoresizingMaskIntoConstraints = NO;
  [clear setTitle:@"Clear" forState:UIControlStateNormal];
  NFBIPAApplyButtonAppearance(clear, NFBIPAButtonStyleText, NFBIPAButtonSizeCompact);
  clear.titleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  clear.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
  [clear addTarget:self action:@selector(clearRecentSearchesTapped) forControlEvents:UIControlEventTouchUpInside];

  [header addSubview:title];
  [header addSubview:clear];
  [NSLayoutConstraint activateConstraints:@[
    [title.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16.0],
    [title.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    [title.trailingAnchor constraintLessThanOrEqualToAnchor:clear.leadingAnchor constant:-12.0],
    [clear.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-16.0],
    [clear.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
    [clear.widthAnchor constraintGreaterThanOrEqualToConstant:52.0],
    [clear.heightAnchor constraintEqualToConstant:44.0]
  ]];
  return header;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return CGFLOAT_MIN;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  if (self.query.length == 0) {
    if (self.recentItems.count == 0) return;
    NSDictionary *item = self.recentItems[(NSUInteger)indexPath.row];
    if ([item[@"type"] isEqualToString:@"user"]) {
      [self performProfileSelection:item];
    } else {
      [self performSearchWithQuery:item[@"query"]];
    }
    return;
  }

  NSInteger row = indexPath.row;
  if (row == 0) {
    [self performSearchWithQuery:self.query];
    return;
  }

  BOOL hasProfileActor = [self profileActorForCurrentQuery].length > 0;
  if (hasProfileActor && row == 1) {
    [self performProfileActorSelection];
    return;
  }

  if (self.loadingSuggestions || self.suggestionErrorMessage.length > 0 || self.suggestedProfiles.count == 0) return;
  NSInteger userIndex = row - 1 - (hasProfileActor ? 1 : 0);
  if (userIndex < 0 || userIndex >= (NSInteger)self.suggestedProfiles.count) return;
  [self performProfileSelection:self.suggestedProfiles[(NSUInteger)userIndex]];
}

@end
