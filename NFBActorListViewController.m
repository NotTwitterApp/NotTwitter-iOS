#import "NFBActorListViewController.h"

#import "NFBAtprotoClient.h"
#import "NFBComposeViewController.h"
#import "NFBLinkRouter.h"
#import "NFBMediaViewerViewController.h"
#import "NFBPostActionCoordinator.h"
#import "NFBPostCell.h"
#import "NFBTheme.h"
#import "NFBTimelineViewController.h"
#import "NFBTweetDetailViewController.h"

#import <SafariServices/SafariServices.h>

typedef NS_ENUM(NSUInteger, NFBActorListMode) {
  NFBActorListModePostStats,
  NFBActorListModeProfileFollows,
  NFBActorListModeStaticActors
};

#import "NFBActorCell.h"

@interface NFBActorCell ()
@property (nonatomic, strong) UIImageView *avatarView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *verifiedBadgeView;
@property (nonatomic, strong) UILabel *handleLabel;
@property (nonatomic, strong) UILabel *followsYouLabel;
@property (nonatomic, strong) UILabel *bioLabel;
@property (nonatomic, strong, readwrite) UIButton *followButton;
@property (nonatomic, strong) UIView *bottomBorder;
@property (nonatomic, copy) NSString *avatarURLString;
@property (nonatomic, strong, readwrite) NSDictionary *profile;
@end

@implementation NFBActorCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
  self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
  if (self) [self buildSubviews];
  return self;
}

- (void)prepareForReuse {
  [super prepareForReuse];
  self.profile = @{};
  self.avatarURLString = nil;
  self.avatarView.image = NFBDefaultAvatarImage() ?: NFBBrandIconImage();
  [self applyTheme];
}

- (void)buildSubviews {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);

  self.avatarView = [[UIImageView alloc] initWithImage:NFBDefaultAvatarImage() ?: NFBBrandIconImage()];
  self.avatarView.translatesAutoresizingMaskIntoConstraints = NO;
  self.avatarView.contentMode = UIViewContentModeScaleAspectFill;
  self.avatarView.clipsToBounds = YES;
  self.avatarView.layer.cornerRadius = 24.0;

  self.nameLabel = [[UILabel alloc] init];
  self.nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.nameLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.nameLabel.numberOfLines = 1;
  self.nameLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.nameLabel setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
  [self.nameLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

  self.verifiedBadgeView = [[UIImageView alloc] initWithImage:NFBVerifiedBadgeImage()];
  self.verifiedBadgeView.translatesAutoresizingMaskIntoConstraints = NO;
  self.verifiedBadgeView.contentMode = UIViewContentModeScaleAspectFit;
  [self.verifiedBadgeView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.verifiedBadgeView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  UIStackView *nameRow = [[UIStackView alloc] initWithArrangedSubviews:@[self.nameLabel, self.verifiedBadgeView]];
  nameRow.translatesAutoresizingMaskIntoConstraints = NO;
  nameRow.axis = UILayoutConstraintAxisHorizontal;
  nameRow.alignment = UIStackViewAlignmentCenter;
  nameRow.spacing = 3.0;
  [nameRow setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [nameRow setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

  self.handleLabel = [[UILabel alloc] init];
  self.handleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.handleLabel.font = NFBFont(14.0, NFBFontWeightRegular);
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
  self.bioLabel.font = NFBFont(14.0, NFBFontWeightRegular);
  self.bioLabel.numberOfLines = 2;
  self.bioLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  UIStackView *textStack = [[UIStackView alloc] initWithArrangedSubviews:@[nameRow, handleRow, self.bioLabel]];
  textStack.translatesAutoresizingMaskIntoConstraints = NO;
  textStack.axis = UILayoutConstraintAxisVertical;
  textStack.alignment = UIStackViewAlignmentLeading;
  textStack.spacing = 1.0;

  self.followButton = [NFBPillButton buttonWithType:UIButtonTypeCustom];
  self.followButton.translatesAutoresizingMaskIntoConstraints = NO;
  self.followButton.layer.cornerRadius = 16.0;
  self.followButton.contentEdgeInsets = UIEdgeInsetsMake(0.0, 14.0, 0.0, 14.0);
  self.followButton.titleLabel.font = NFBFont(14.0, NFBFontWeightHeavy);
  self.followButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.followButton addTarget:self action:@selector(followTapped) forControlEvents:UIControlEventTouchUpInside];

  self.bottomBorder = [[UIView alloc] init];
  self.bottomBorder.translatesAutoresizingMaskIntoConstraints = NO;

  [self.contentView addSubview:self.avatarView];
  [self.contentView addSubview:textStack];
  [self.contentView addSubview:self.followButton];
  [self.contentView addSubview:self.bottomBorder];

  [NSLayoutConstraint activateConstraints:@[
    [self.avatarView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16.0],
    [self.avatarView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:12.0],
    [self.avatarView.widthAnchor constraintEqualToConstant:48.0],
    [self.avatarView.heightAnchor constraintEqualToConstant:48.0],
    [textStack.leadingAnchor constraintEqualToAnchor:self.avatarView.trailingAnchor constant:12.0],
    [textStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:11.0],
    [textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.followButton.leadingAnchor constant:-12.0],
    [textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12.0],
    [self.followButton.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
    [self.followButton.centerYAnchor constraintEqualToAnchor:self.avatarView.centerYAnchor],
    [self.followButton.heightAnchor constraintEqualToConstant:32.0],
    [self.followButton.widthAnchor constraintGreaterThanOrEqualToConstant:86.0],
    [nameRow.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
    [handleRow.widthAnchor constraintLessThanOrEqualToAnchor:textStack.widthAnchor],
    [self.followsYouLabel.heightAnchor constraintEqualToConstant:18.0],
    [self.followsYouLabel.widthAnchor constraintGreaterThanOrEqualToConstant:70.0],
    [self.verifiedBadgeView.widthAnchor constraintEqualToConstant:15.0],
    [self.verifiedBadgeView.heightAnchor constraintEqualToConstant:15.0],
    [self.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:74.0],
    [self.bottomBorder.leadingAnchor constraintEqualToAnchor:textStack.leadingAnchor],
    [self.bottomBorder.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
    [self.bottomBorder.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
    [self.bottomBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  [self applyTheme];
}

- (void)applyTheme {
  NFBIPAApplyTableCellAppearance(self, UITableViewCellSelectionStyleNone);
  self.nameLabel.textColor = NFBColorText();
  self.handleLabel.textColor = NFBColorSecondaryText();
  NFBIPAApplyFollowsYouBadgeAppearance(self.followsYouLabel);
  self.bioLabel.textColor = NFBColorText();
  NFBIPAApplyTableSeparatorAppearance(self.bottomBorder);
}

- (void)configureWithProfile:(NSDictionary *)profile {
  self.profile = profile ?: @{};
  [self applyTheme];
  self.nameLabel.text = [NFBAtprotoClient displayNameForProfile:self.profile];
  self.handleLabel.text = [@"@" stringByAppendingString:[NFBAtprotoClient handleForProfile:self.profile]];
  self.followsYouLabel.hidden = !NFBIPAProfileFollowsViewer(self.profile);
  NSString *description = [self.profile[@"description"] isKindOfClass:NSString.class] ? self.profile[@"description"] : @"";
  self.bioLabel.hidden = description.length == 0;
  self.bioLabel.text = description;
  self.verifiedBadgeView.hidden = ![NFBAtprotoClient isProfileVerified:self.profile];
  [NFBPostActionCoordinator configureFollowButton:self.followButton profile:self.profile overDarkBackground:NO];
  [self loadAvatarURL:[NFBAtprotoClient avatarURLForProfile:self.profile]];
}

- (void)loadAvatarURL:(NSString *)urlString {
  self.avatarURLString = urlString ?: @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([self.avatarURLString isEqualToString:urlString]) self.avatarView.image = image;
    });
  }] resume];
}

- (void)followTapped {
  [self.delegate actorCellDidTapFollow:self];
}

@end

@interface NFBActorListViewController () <UITableViewDataSource, UITableViewDelegate, NFBPostCellDelegate, NFBActorCellDelegate, NFBMediaViewerViewControllerDelegate>
@property (nonatomic, assign) NFBActorListMode mode;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIRefreshControl *refreshControl;
@property (nonatomic, strong) UIView *tabsView;
@property (nonatomic, strong) UIStackView *tabsStack;
@property (nonatomic, strong) NSLayoutConstraint *tabsHeightConstraint;
@property (nonatomic, strong) NSMutableArray<UIButton *> *tabButtons;
@property (nonatomic, strong) UIImageView *emptyLoadingView;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, copy) NSString *cursor;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL endReached;
@property (nonatomic, copy) NSString *selectedID;
@property (nonatomic, strong) NSDictionary *post;
@property (nonatomic, strong) NSDictionary *profile;
@property (nonatomic, copy) NSString *actor;
@property (nonatomic, copy) NSString *staticTitle;
@property (nonatomic, strong) NFBPostActionCoordinator *postActionCoordinator;
@property (nonatomic, assign) BOOL refreshSuccessSoundPending;
@end

@implementation NFBActorListViewController

- (instancetype)initWithPost:(NSDictionary *)post selectedType:(NSString *)type {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _mode = NFBActorListModePostStats;
    _post = [post copy] ?: @{};
    _selectedID = [(type.length > 0 ? type : @"likes") copy];
    _items = [NSMutableArray array];
    _tabButtons = [NSMutableArray array];
  }
  return self;
}

- (instancetype)initWithProfile:(NSDictionary *)profile actor:(NSString *)actor selectedKind:(NSString *)kind {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _mode = NFBActorListModeProfileFollows;
    _profile = [profile copy] ?: @{};
    _actor = [actor copy] ?: @"";
    _selectedID = [(kind.length > 0 ? kind : @"followers") copy];
    _items = [NSMutableArray array];
    _tabButtons = [NSMutableArray array];
  }
  return self;
}

- (instancetype)initWithActors:(NSArray<NSDictionary *> *)actors title:(NSString *)title {
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _mode = NFBActorListModeStaticActors;
    _staticTitle = [(title.length > 0 ? title : @"People") copy];
    _selectedID = @"actors";
    _items = [NSMutableArray array];
    for (NSDictionary *actor in actors ?: @[]) {
      if ([actor isKindOfClass:NSDictionary.class]) [_items addObject:actor];
    }
    _tabButtons = [NSMutableArray array];
  }
  return self;
}

- (NFBPostActionCoordinator *)postActionCoordinator {
  if (!_postActionCoordinator) {
    _postActionCoordinator = [[NFBPostActionCoordinator alloc] initWithPresentingViewController:self];
    __weak typeof(self) weakSelf = self;
    _postActionCoordinator.postUpdateHandler = ^(NSDictionary *updatedPost, NSDictionary *originalPost) {
      [weakSelf applyUpdatedPost:updatedPost originalPost:originalPost];
    };
    _postActionCoordinator.profileUpdateHandler = ^(NSDictionary *updatedProfile, NSDictionary *originalProfile) {
      [weakSelf applyUpdatedProfile:updatedProfile originalProfile:originalProfile];
    };
    _postActionCoordinator.reloadHandler = ^{
      [weakSelf reloadReplacing:YES];
    };
    _postActionCoordinator.deleteHandler = ^(NSDictionary *deletedPost) {
      [weakSelf removeDeletedPost:deletedPost];
    };
  }
  _postActionCoordinator.presentingViewController = self;
  return _postActionCoordinator;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(backTapped));
  [self configureTitle];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];

  self.tabsView = [[UIView alloc] init];
  self.tabsView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabsView.backgroundColor = NFBColorBackground();
  self.tabsView.hidden = self.mode == NFBActorListModeStaticActors;

  self.tabsStack = [[UIStackView alloc] init];
  self.tabsStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.tabsStack.axis = UILayoutConstraintAxisHorizontal;
  self.tabsStack.alignment = UIStackViewAlignmentFill;
  self.tabsStack.distribution = UIStackViewDistributionFillEqually;
  [self.tabsView addSubview:self.tabsStack];

  UIView *tabsBorder = [[UIView alloc] init];
  tabsBorder.translatesAutoresizingMaskIntoConstraints = NO;
  tabsBorder.backgroundColor = NFBColorBorder();
  [self.tabsView addSubview:tabsBorder];

  self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
  self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.rowHeight = UITableViewAutomaticDimension;
  self.tableView.estimatedRowHeight = 92.0;
  NFBIPAApplyTableViewAppearance(self.tableView);
  [self.tableView registerClass:NFBActorCell.class forCellReuseIdentifier:@"actor"];
  [self.tableView registerClass:NFBPostCell.class forCellReuseIdentifier:@"post"];
  if (self.mode != NFBActorListModeStaticActors) {
    self.refreshControl = NFBCreateRefreshControl(self, @selector(refreshPulled:));
    self.tableView.refreshControl = self.refreshControl;
  }

  self.emptyLoadingView = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
  self.emptyLoadingView.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLoadingView.contentMode = UIViewContentModeScaleAspectFit;
  self.emptyLoadingView.tintColor = NFBColorAccent();
  self.emptyLoadingView.hidden = YES;

  self.emptyLabel = [[UILabel alloc] init];
  self.emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.emptyLabel.textAlignment = NSTextAlignmentCenter;
  self.emptyLabel.numberOfLines = 0;
  self.emptyLabel.font = NFBFont(16.0, NFBFontWeightBold);
  self.emptyLabel.textColor = NFBColorSecondaryText();
  self.emptyLabel.hidden = YES;

  [self.view addSubview:self.tabsView];
  [self.view addSubview:self.tableView];
  [self.view addSubview:self.emptyLoadingView];
  [self.view addSubview:self.emptyLabel];
  self.tabsHeightConstraint = [self.tabsView.heightAnchor constraintEqualToConstant:(self.mode == NFBActorListModeStaticActors ? 0.0 : 53.0)];
  [NSLayoutConstraint activateConstraints:@[
    [self.tabsView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
    [self.tabsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tabsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    self.tabsHeightConstraint,
    [self.tabsStack.topAnchor constraintEqualToAnchor:self.tabsView.topAnchor],
    [self.tabsStack.leadingAnchor constraintEqualToAnchor:self.tabsView.leadingAnchor],
    [self.tabsStack.trailingAnchor constraintEqualToAnchor:self.tabsView.trailingAnchor],
    [self.tabsStack.bottomAnchor constraintEqualToAnchor:self.tabsView.bottomAnchor],
    [tabsBorder.leadingAnchor constraintEqualToAnchor:self.tabsView.leadingAnchor],
    [tabsBorder.trailingAnchor constraintEqualToAnchor:self.tabsView.trailingAnchor],
    [tabsBorder.bottomAnchor constraintEqualToAnchor:self.tabsView.bottomAnchor],
    [tabsBorder.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
    [self.tableView.topAnchor constraintEqualToAnchor:self.tabsView.bottomAnchor],
    [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.emptyLoadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [self.emptyLoadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    [self.emptyLoadingView.widthAnchor constraintEqualToConstant:32.0],
    [self.emptyLoadingView.heightAnchor constraintEqualToConstant:32.0],
    [self.emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:36.0],
    [self.emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-36.0],
    [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
  ]];

  [self rebuildTabs];
  if (self.mode == NFBActorListModeStaticActors) {
    [self.tableView reloadData];
    [self updateEmptyState:self.items.count == 0 ? [self emptyMessage] : @""];
  } else {
    [self reloadReplacing:YES];
  }
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSArray<NSDictionary *> *)tabDefinitions {
  if (self.mode == NFBActorListModeStaticActors) return @[];
  if (self.mode == NFBActorListModePostStats) {
    return @[
      @{@"id": @"reposts", @"title": @"Retweets"},
      @{@"id": @"quotes", @"title": @"Quote Tweets"},
      @{@"id": @"likes", @"title": @"Likes"}
    ];
  }
  return @[
    @{@"id": @"following", @"title": @"Following"},
    @{@"id": @"followers", @"title": @"Followers"},
    @{@"id": @"known", @"title": @"People You Know"}
  ];
}

- (void)rebuildTabs {
  for (UIView *view in self.tabsStack.arrangedSubviews) {
    [self.tabsStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  [self.tabButtons removeAllObjects];
  NSArray<NSDictionary *> *tabs = [self tabDefinitions];
  for (NSUInteger index = 0; index < tabs.count; index++) {
    NSDictionary *tab = tabs[index];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = (NSInteger)index;
    button.titleLabel.font = NFBFont(15.0, NFBFontWeightHeavy);
    button.titleLabel.numberOfLines = 1;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.72;
    [button setTitle:tab[@"title"] forState:UIControlStateNormal];
    [button addTarget:self action:@selector(tabTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIView *underline = [[UIView alloc] init];
    underline.translatesAutoresizingMaskIntoConstraints = NO;
    underline.tag = 9913;
    underline.layer.cornerRadius = 2.0;
    [button addSubview:underline];
    [NSLayoutConstraint activateConstraints:@[
      [underline.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
      [underline.bottomAnchor constraintEqualToAnchor:button.bottomAnchor],
      [underline.widthAnchor constraintEqualToConstant:56.0],
      [underline.heightAnchor constraintEqualToConstant:4.0]
    ]];
    [self.tabsStack addArrangedSubview:button];
    [self.tabButtons addObject:button];
  }
  [self updateTabSelection];
}

- (void)updateTabSelection {
  NSArray<NSDictionary *> *tabs = [self tabDefinitions];
  for (NSUInteger index = 0; index < self.tabButtons.count; index++) {
    UIButton *button = self.tabButtons[index];
    NSString *identifier = index < tabs.count ? tabs[index][@"id"] : @"";
    BOOL selected = [identifier isEqualToString:self.selectedID];
    [button setTitleColor:selected ? NFBColorText() : NFBColorSecondaryText() forState:UIControlStateNormal];
    for (UIView *subview in button.subviews) {
      if (subview.tag == 9913) {
        subview.hidden = !selected;
        subview.backgroundColor = NFBColorAccent();
      }
    }
  }
}

- (void)configureTitle {
  NSString *title = @"";
  if (self.mode == NFBActorListModePostStats) {
    if ([self.selectedID isEqualToString:@"reposts"]) title = @"Retweeted by";
    else if ([self.selectedID isEqualToString:@"quotes"]) title = @"Quote Tweets";
    else title = @"Liked by";
  } else if (self.mode == NFBActorListModeStaticActors) {
    title = self.staticTitle.length > 0 ? self.staticTitle : @"People";
  } else {
    if ([self.selectedID isEqualToString:@"following"]) title = @"Following";
    else if ([self.selectedID isEqualToString:@"known"]) title = @"Followers you know";
    else title = @"Followers";
  }
  self.title = title;
  self.navigationItem.titleView = NFBTitleView(title, nil);
}

- (void)tabTapped:(UIButton *)sender {
  NSArray<NSDictionary *> *tabs = [self tabDefinitions];
  if (sender.tag < 0 || sender.tag >= (NSInteger)tabs.count) return;
  NSString *identifier = tabs[(NSUInteger)sender.tag][@"id"];
  if (![identifier isKindOfClass:NSString.class] || [identifier isEqualToString:self.selectedID]) return;
  self.selectedID = identifier;
  [self configureTitle];
  [self updateTabSelection];
  [self reloadReplacing:YES];
}

- (void)reloadReplacing:(BOOL)replacing {
  if (self.mode == NFBActorListModeStaticActors) {
    [self.tableView reloadData];
    [self updateEmptyState:self.items.count == 0 ? [self emptyMessage] : @""];
    [self.refreshControl endRefreshing];
    return;
  }
  if (replacing) {
    self.cursor = nil;
    self.endReached = NO;
    [self.items removeAllObjects];
    [self.tableView reloadData];
  }
  [self fetchNextPage];
}

- (void)refreshPulled:(UIRefreshControl *)sender {
  (void)sender;
  self.refreshSuccessSoundPending = YES;
  NFBPlaySound(@"pull.aac");
  [self reloadReplacing:YES];
}

- (void)fetchNextPage {
  if (self.mode == NFBActorListModeStaticActors) {
    [self.refreshControl endRefreshing];
    [self updateEmptyState:self.items.count == 0 ? [self emptyMessage] : @""];
    return;
  }
  if (self.loading || self.endReached) {
    self.refreshSuccessSoundPending = NO;
    [self.refreshControl endRefreshing];
    return;
  }
  self.loading = YES;
  [self updateEmptyState:@"Loading..."];
  __weak typeof(self) weakSelf = self;
  NFBAtprotoArrayCompletion completion = ^(NSArray<NSDictionary *> *items, NSString *cursor, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      strongSelf.loading = NO;
      BOOL shouldPlayRefreshSound = strongSelf.refreshSuccessSoundPending;
      strongSelf.refreshSuccessSoundPending = NO;
      [strongSelf.refreshControl endRefreshing];
      if (error) {
        [strongSelf updateEmptyState:error.localizedDescription ?: @"Could not load."];
        return;
      }
      if (shouldPlayRefreshSound) NFBPlaySound(@"refresh.aac");
      if (items.count == 0) strongSelf.endReached = YES;
      [strongSelf.items addObjectsFromArray:items ?: @[]];
      strongSelf.cursor = cursor ?: @"";
      if (cursor.length == 0) strongSelf.endReached = YES;
      [strongSelf.tableView reloadData];
      [strongSelf updateEmptyState:strongSelf.items.count == 0 ? [strongSelf emptyMessage] : @""];
    });
  };
  if (self.mode == NFBActorListModePostStats) {
    [[NFBAtprotoClient sharedClient] fetchPostStatsForPost:self.post type:self.selectedID cursor:self.cursor completion:completion];
  } else {
    [[NFBAtprotoClient sharedClient] fetchProfileActorsForActor:self.actor kind:self.selectedID cursor:self.cursor completion:completion];
  }
}

- (NSString *)emptyMessage {
  if (self.mode == NFBActorListModePostStats && [self.selectedID isEqualToString:@"quotes"]) return @"No Quote Tweets yet";
  if (self.mode == NFBActorListModePostStats && [self.selectedID isEqualToString:@"reposts"]) return @"No Retweets yet";
  if (self.mode == NFBActorListModePostStats) return @"No Likes yet";
  if ([self.selectedID isEqualToString:@"known"]) return @"No followers you know yet";
  return @"No people yet";
}

- (void)updateEmptyState:(NSString *)message {
  BOOL loading = [message isEqualToString:@"Loading..."];
  self.emptyLoadingView.hidden = !loading;
  self.emptyLabel.hidden = loading || message.length == 0;
  self.emptyLabel.text = loading ? @"" : message;
  if (loading) NFBStartLoadingAnimation(self.emptyLoadingView);
  else NFBStopLoadingAnimation(self.emptyLoadingView);
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  self.view.backgroundColor = NFBColorBackground();
  self.tabsView.backgroundColor = NFBColorBackground();
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.emptyLabel.textColor = NFBColorSecondaryText();
  self.emptyLoadingView.tintColor = NFBColorAccent();
  NFBUpdateRefreshControlAppearance(self.refreshControl);
  [self updateTabSelection];
  NFBApplyNavigationAppearance(self.navigationController);
  [self.tableView reloadData];
}

- (void)backTapped {
  [self.navigationController popViewControllerAnimated:YES];
}

- (BOOL)showsPosts {
  return self.mode == NFBActorListModePostStats && [self.selectedID isEqualToString:@"quotes"];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  (void)tableView;
  (void)section;
  return (NSInteger)self.items.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  if ([self showsPosts]) {
    NFBPostCell *cell = [tableView dequeueReusableCellWithIdentifier:@"post" forIndexPath:indexPath];
    cell.delegate = self;
    NSDictionary *item = self.items[(NSUInteger)indexPath.row];
    [cell configureWithFeedItem:item];
    if (@available(iOS 13.0, *)) {
      NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
      [cell setMoreMenu:[[self postActionCoordinator] contextMenuForPost:post]];
    }
    return cell;
  }
  NFBActorCell *cell = [tableView dequeueReusableCellWithIdentifier:@"actor" forIndexPath:indexPath];
  cell.delegate = self;
  [cell configureWithProfile:self.items[(NSUInteger)indexPath.row]];
  return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  (void)tableView;
  if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return;
  if ([self showsPosts]) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)indexPath.row]];
    NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
    [self.navigationController pushViewController:detail animated:YES];
    return;
  }
  [[self postActionCoordinator] performGoToProfile:self.items[(NSUInteger)indexPath.row]];
}

- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
  (void)tableView;
  (void)point;
  if (![self showsPosts]) return nil;
  if (indexPath.row < 0 || indexPath.row >= (NSInteger)self.items.count) return nil;
  if (@available(iOS 13.0, *)) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:self.items[(NSUInteger)indexPath.row]];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if (uri.length == 0) return nil;
    __weak typeof(self) weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:uri
                                                  previewProvider:^UIViewController * _Nullable{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      NFBTweetDetailViewController *preview = [[NFBTweetDetailViewController alloc] initWithPost:post];
      CGFloat width = strongSelf ? MIN(390.0, MAX(300.0, CGRectGetWidth(strongSelf.view.bounds) - 28.0)) : 360.0;
      preview.preferredContentSize = CGSizeMake(width, 520.0);
      return preview;
    } actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
      (void)suggestedActions;
      __strong typeof(weakSelf) strongSelf = weakSelf;
      return strongSelf ? [[strongSelf postActionCoordinator] contextMenuForPost:post] : nil;
    }];
  }
  return nil;
}

- (void)tableView:(UITableView *)tableView willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionCommitAnimating>)animator {
  (void)tableView;
  if (@available(iOS 13.0, *)) {
    id identifier = configuration.identifier;
    NSString *uri = [identifier isKindOfClass:NSString.class] ? (NSString *)identifier : @"";
    if (uri.length == 0) return;
    __weak typeof(self) weakSelf = self;
    [animator addCompletion:^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      NSDictionary *post = [strongSelf postForURI:uri];
      if (strongSelf && post.count > 0) {
        NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:post];
        [strongSelf.navigationController pushViewController:detail animated:YES];
      }
    }];
  }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  CGFloat distance = scrollView.contentSize.height - (scrollView.contentOffset.y + CGRectGetHeight(scrollView.bounds));
  if (distance < 360.0) [self fetchNextPage];
}

- (NSDictionary *)postForURI:(NSString *)uri {
  if (uri.length == 0) return @{};
  for (NSDictionary *item in self.items) {
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *candidate = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if ([candidate isEqualToString:uri]) return post;
  }
  return @{};
}

- (void)applyUpdatedPost:(NSDictionary *)updatedPost originalPost:(NSDictionary *)originalPost {
  NSString *targetURI = [originalPost[@"uri"] isKindOfClass:NSString.class] ? originalPost[@"uri"] : @"";
  if (targetURI.length == 0 || ![updatedPost isKindOfClass:NSDictionary.class]) return;
  NSMutableArray<NSIndexPath *> *reloadPaths = [NSMutableArray array];
  for (NSUInteger index = 0; index < self.items.count; index++) {
    NSDictionary *item = self.items[index];
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    if (![uri isEqualToString:targetURI]) continue;
    NSMutableDictionary *updatedItem = [item mutableCopy];
    updatedItem[@"post"] = updatedPost;
    self.items[index] = updatedItem;
    [reloadPaths addObject:[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]];
  }
  if (reloadPaths.count > 0) {
    [self.tableView reloadRowsAtIndexPaths:reloadPaths withRowAnimation:UITableViewRowAnimationNone];
  }
}

- (void)applyUpdatedProfile:(NSDictionary *)updatedProfile originalProfile:(NSDictionary *)originalProfile {
  NSString *targetDID = [originalProfile[@"did"] isKindOfClass:NSString.class] ? originalProfile[@"did"] : @"";
  if (targetDID.length == 0) targetDID = [updatedProfile[@"did"] isKindOfClass:NSString.class] ? updatedProfile[@"did"] : @"";
  if (targetDID.length == 0) return;
  for (NSUInteger index = 0; index < self.items.count; index++) {
    NSDictionary *profile = self.items[index];
    NSString *did = [profile[@"did"] isKindOfClass:NSString.class] ? profile[@"did"] : @"";
    if (![did isEqualToString:targetDID]) continue;
    self.items[index] = updatedProfile ?: @{};
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:(NSInteger)index inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
    break;
  }
}

- (void)removeDeletedPost:(NSDictionary *)deletedPost {
  NSString *targetURI = [deletedPost[@"uri"] isKindOfClass:NSString.class] ? deletedPost[@"uri"] : @"";
  if (targetURI.length == 0) return;
  NSIndexSet *indexes = [self.items indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
    (void)idx;
    (void)stop;
    NSDictionary *post = [NFBAtprotoClient postFromFeedItem:item];
    NSString *uri = [post[@"uri"] isKindOfClass:NSString.class] ? post[@"uri"] : @"";
    return [uri isEqualToString:targetURI];
  }];
  if (indexes.count == 0) return;
  NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
  [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
    (void)stop;
    [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)idx inSection:0]];
  }];
  [self.items removeObjectsAtIndexes:indexes];
  [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)actorCellDidTapFollow:(NFBActorCell *)cell {
  [[self postActionCoordinator] performFollowForProfile:cell.profile sourceView:cell.followButton completion:nil];
}

- (void)postCellDidTapReply:(NFBPostCell *)cell {
  [[self postActionCoordinator] performReplyForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapRepost:(NFBPostCell *)cell {
  [[self postActionCoordinator] performRepostForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapLike:(NFBPostCell *)cell {
  [[self postActionCoordinator] performLikeForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapBookmark:(NFBPostCell *)cell {
  [[self postActionCoordinator] performBookmarkForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapShare:(NFBPostCell *)cell {
  [[self postActionCoordinator] performShareForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapMore:(NFBPostCell *)cell {
  [[self postActionCoordinator] presentMoreMenuForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidLongPress:(NFBPostCell *)cell {
  [[self postActionCoordinator] presentMoreMenuForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}] sourceView:nil];
}

- (void)postCellDidTapAuthor:(NFBPostCell *)cell {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NSDictionary *author = [post[@"author"] isKindOfClass:NSDictionary.class] ? post[@"author"] : @{};
  [[self postActionCoordinator] performGoToProfile:author];
}

- (void)postCell:(NFBPostCell *)cell didTapLinkURL:(NSURL *)url {
  (void)cell;
  NFBOpenTweetTextURL(url, self);
}

- (void)postCell:(NFBPostCell *)cell didTapMediaAtIndex:(NSUInteger)index transitionSource:(NFBMediaTransitionSource *)transitionSource {
  NSDictionary *post = [NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}];
  NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithMediaItems:[NFBAtprotoClient mediaItemsForPost:post] initialIndex:index post:post];
  viewer.transitionSource = transitionSource;
  viewer.delegate = self;
  [self presentViewController:viewer animated:YES completion:nil];
}

- (void)postCellDidTapExternalCard:(NFBPostCell *)cell {
  NSDictionary *card = [NFBAtprotoClient externalCardForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}]];
  NSString *urlString = [card[@"url"] isKindOfClass:NSString.class] ? card[@"url"] : @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
  safari.preferredControlTintColor = NFBColorAccent();
  [self presentViewController:safari animated:YES completion:nil];
}

- (void)postCellDidTapExternalCardWebsite:(NFBPostCell *)cell {
  [self postCellDidTapExternalCard:cell];
}

- (void)postCellDidTapQuotedPost:(NFBPostCell *)cell {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}]];
  if (!quotedPost) return;
  NFBTweetDetailViewController *detail = [[NFBTweetDetailViewController alloc] initWithPost:quotedPost];
  [self.navigationController pushViewController:detail animated:YES];
}

- (void)postCell:(NFBPostCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index transitionSource:(NFBMediaTransitionSource *)transitionSource {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}]];
  NFBMediaViewerViewController *viewer = [[NFBMediaViewerViewController alloc] initWithMediaItems:[NFBAtprotoClient mediaItemsForPost:quotedPost ?: @{}] initialIndex:index post:quotedPost ?: @{}];
  viewer.transitionSource = transitionSource;
  viewer.delegate = self;
  [self presentViewController:viewer animated:YES completion:nil];
}

- (void)postCellDidTapQuotedExternalCard:(NFBPostCell *)cell {
  NSDictionary *quotedPost = [NFBAtprotoClient quotedPostForPost:[NFBAtprotoClient postFromFeedItem:cell.feedItem ?: @{}]];
  NSDictionary *card = [NFBAtprotoClient externalCardForPost:quotedPost ?: @{}];
  NSString *urlString = [card[@"url"] isKindOfClass:NSString.class] ? card[@"url"] : @"";
  NSURL *url = [NSURL URLWithString:urlString ?: @""];
  if (!url) return;
  SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
  safari.preferredControlTintColor = NFBColorAccent();
  [self presentViewController:safari animated:YES completion:nil];
}

- (void)postCellDidTapQuotedExternalCardWebsite:(NFBPostCell *)cell {
  [self postCellDidTapQuotedExternalCard:cell];
}

- (void)mediaViewerViewController:(NFBMediaViewerViewController *)viewer didUpdatePost:(NSDictionary *)updatedPost originalPost:(NSDictionary *)originalPost {
  (void)viewer;
  [self applyUpdatedPost:updatedPost originalPost:originalPost];
}

@end
