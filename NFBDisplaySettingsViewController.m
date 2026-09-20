#import "NFBDisplaySettingsViewController.h"

#import "NFBTheme.h"

static NSInteger const NFBDisplayModeTitleTag = 801;
static NSInteger const NFBDisplayModeCheckTag = 802;
static NSInteger const NFBDisplayModePreviewTag = 803;
static NSInteger const NFBFontSizeStopBaseTag = 840;

@interface NFBAccentColorCell : UICollectionViewCell

@property (nonatomic, strong) UILabel *colorLabel;
@property (nonatomic, strong) UIImageView *checkView;

- (void)configureWithColorID:(NSInteger)colorID name:(NSString *)name selected:(BOOL)selected;

@end

@implementation NFBAccentColorCell

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = UIColor.clearColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    self.colorLabel = [[UILabel alloc] init];
    self.colorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.colorLabel.textColor = UIColor.whiteColor;
    self.colorLabel.textAlignment = NSTextAlignmentCenter;
    self.colorLabel.layer.masksToBounds = YES;
    self.colorLabel.layer.cornerRadius = 18.0;
    self.colorLabel.font = NFBFont(14.0, NFBFontWeightBold);

	    self.checkView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_circle")];
    self.checkView.translatesAutoresizingMaskIntoConstraints = NO;
    self.checkView.contentMode = UIViewContentModeScaleAspectFit;

    [self.contentView addSubview:self.colorLabel];
    [self.contentView addSubview:self.checkView];

    [NSLayoutConstraint activateConstraints:@[
      [self.colorLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
      [self.colorLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
      [self.colorLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
      [self.colorLabel.heightAnchor constraintEqualToConstant:36.0],
      [self.checkView.topAnchor constraintEqualToAnchor:self.colorLabel.bottomAnchor constant:12.0],
      [self.checkView.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
      [self.checkView.widthAnchor constraintEqualToConstant:24.0],
      [self.checkView.heightAnchor constraintEqualToConstant:24.0]
    ]];
  }
  return self;
}

- (void)configureWithColorID:(NSInteger)colorID name:(NSString *)name selected:(BOOL)selected {
  self.colorLabel.text = name;
  self.colorLabel.backgroundColor = NFBAccentColorForID(colorID);
	  self.checkView.image = NFBTemplateIcon(selected ? @"nfb_checkmark_circle" : @"nfb_circle");
  self.checkView.tintColor = selected ? NFBColorAccent() : NFBColorSecondaryText();
}

@end

@interface NFBDisplaySettingsViewController () <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UILabel *headerLabel;
@property (nonatomic, strong) UICollectionView *colorCollectionView;
@property (nonatomic, strong) NSLayoutConstraint *colorCollectionHeightConstraint;
@property (nonatomic, copy) NSArray<NSDictionary *> *colorItems;
@property (nonatomic, copy) NSArray<UIControl *> *displayControls;
@property (nonatomic, strong) UILabel *fontSizePreviewLabel;
@property (nonatomic, strong) UIView *fontSizeTrackView;
@property (nonatomic, strong) UIView *fontSizeTrackFillView;
@property (nonatomic, strong) NSLayoutConstraint *fontSizeTrackFillWidthConstraint;
@property (nonatomic, copy) NSArray<UIButton *> *fontSizeStopButtons;
@property (nonatomic, strong) UIControl *standardSiteArticlesRowControl;
@property (nonatomic, strong) UISwitch *standardSiteArticlesSwitch;
@property (nonatomic, strong) UIView *standardSiteArticlesBorder;

@end

@implementation NFBDisplaySettingsViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.navigationItem.titleView = NFBTitleView(@"Display", nil);
  [self configureNavigationButton];

  self.colorItems = @[
    @{@"id": @1, @"name": NFBAccentColorNameForID(1)},
    @{@"id": @2, @"name": NFBAccentColorNameForID(2)},
    @{@"id": @3, @"name": NFBAccentColorNameForID(3)},
    @{@"id": @4, @"name": NFBAccentColorNameForID(4)},
    @{@"id": @5, @"name": NFBAccentColorNameForID(5)},
    @{@"id": @6, @"name": NFBAccentColorNameForID(6)}
  ];

  [self buildContent];
  [self refreshTheme];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:NFBThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  [self configureNavigationButton];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  self.navigationController.interactivePopGestureRecognizer.enabled = self.navigationController.viewControllers.count > 1;
  self.navigationController.interactivePopGestureRecognizer.delegate = nil;
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  [self.colorCollectionView.collectionViewLayout invalidateLayout];
  [self.colorCollectionView layoutIfNeeded];
  CGFloat height = self.colorCollectionView.collectionViewLayout.collectionViewContentSize.height;
  if (height > 0.0 && fabs(self.colorCollectionHeightConstraint.constant - height) > 1.0) {
    self.colorCollectionHeightConstraint.constant = height;
  }
  [self updateFontSizeControls];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)buildContent {
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
  self.contentStack.spacing = 0.0;

  [self.view addSubview:self.scrollView];
  [self.scrollView addSubview:self.contentStack];

  UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [self.scrollView.topAnchor constraintEqualToAnchor:guide.topAnchor],
    [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
    [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.leadingAnchor],
    [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.trailingAnchor],
    [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
    [self.contentStack.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]
  ]];

  self.headerLabel = [[UILabel alloc] init];
  self.headerLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.headerLabel.text = @"Customize how Not Twitter looks on this device.";
  self.headerLabel.numberOfLines = 0;
  self.headerLabel.textAlignment = NSTextAlignmentLeft;
  self.headerLabel.lineBreakMode = NSLineBreakByWordWrapping;
  self.headerLabel.font = NFBFont(13.0, NFBFontWeightRegular);

  UIView *headerContainer = [[UIView alloc] init];
  headerContainer.translatesAutoresizingMaskIntoConstraints = NO;
  [headerContainer addSubview:self.headerLabel];
  [NSLayoutConstraint activateConstraints:@[
    [self.headerLabel.topAnchor constraintEqualToAnchor:headerContainer.topAnchor constant:16.0],
    [self.headerLabel.leadingAnchor constraintEqualToAnchor:headerContainer.leadingAnchor constant:16.0],
    [self.headerLabel.trailingAnchor constraintEqualToAnchor:headerContainer.trailingAnchor constant:-16.0],
    [self.headerLabel.bottomAnchor constraintEqualToAnchor:headerContainer.bottomAnchor constant:-8.0]
  ]];
  [self.contentStack addArrangedSubview:headerContainer];

  [self.contentStack addArrangedSubview:[self sectionTitle:@"Font size"]];
  [self.contentStack addArrangedSubview:[self fontSizeView]];
  [self.contentStack addArrangedSubview:[self sectionSpacer:20.0]];
  [self.contentStack addArrangedSubview:[self sectionTitle:@"Background"]];
  [self.contentStack addArrangedSubview:[self displayModesView]];
  [self.contentStack addArrangedSubview:[self sectionSpacer:20.0]];
  [self.contentStack addArrangedSubview:[self sectionTitle:@"Content"]];
  [self.contentStack addArrangedSubview:[self standardSiteArticlesRowView]];
  [self.contentStack addArrangedSubview:[self sectionSpacer:20.0]];
  [self.contentStack addArrangedSubview:[self sectionTitle:@"Color"]];
  [self.contentStack addArrangedSubview:[self colorCollectionContainer]];
}

- (UIView *)sectionTitle:(NSString *)title {
  UIView *wrapper = [[UIView alloc] init];
  wrapper.translatesAutoresizingMaskIntoConstraints = NO;
  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = title;
  label.font = NFBFont(15.0, NFBFontWeightHeavy);
  label.textColor = NFBColorText();
  [wrapper addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [wrapper.heightAnchor constraintEqualToConstant:28.0],
    [label.leadingAnchor constraintEqualToAnchor:wrapper.leadingAnchor constant:16.0],
    [label.trailingAnchor constraintEqualToAnchor:wrapper.trailingAnchor constant:-16.0],
    [label.centerYAnchor constraintEqualToAnchor:wrapper.centerYAnchor]
  ]];
  return wrapper;
}

- (UIView *)sectionSpacer:(CGFloat)height {
  UIView *spacer = [[UIView alloc] init];
  spacer.translatesAutoresizingMaskIntoConstraints = NO;
  [spacer.heightAnchor constraintEqualToConstant:height].active = YES;
  return spacer;
}

- (UIView *)fontSizeView {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *previewCard = [[UIView alloc] init];
  previewCard.translatesAutoresizingMaskIntoConstraints = NO;
  previewCard.layer.cornerRadius = 16.0;
  previewCard.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
  previewCard.clipsToBounds = YES;

  self.fontSizePreviewLabel = [[UILabel alloc] init];
  self.fontSizePreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
  self.fontSizePreviewLabel.text = @"At the heart of Not Twitter are short messages called Tweets — just like this one — which can include photos, videos, links and text.";
  self.fontSizePreviewLabel.numberOfLines = 0;
  self.fontSizePreviewLabel.lineBreakMode = NSLineBreakByWordWrapping;

  UILabel *smallLabel = [[UILabel alloc] init];
  smallLabel.translatesAutoresizingMaskIntoConstraints = NO;
  smallLabel.text = @"Aa";
  smallLabel.font = NFBFont(13.0, NFBFontWeightBold);
  smallLabel.textAlignment = NSTextAlignmentCenter;
  smallLabel.accessibilityLabel = @"Decrease text size.";

  UILabel *largeLabel = [[UILabel alloc] init];
  largeLabel.translatesAutoresizingMaskIntoConstraints = NO;
  largeLabel.text = @"Aa";
  largeLabel.font = NFBFont(22.0, NFBFontWeightBold);
  largeLabel.textAlignment = NSTextAlignmentCenter;
  largeLabel.accessibilityLabel = @"Increase text size.";

  UIView *trackContainer = [[UIView alloc] init];
  trackContainer.translatesAutoresizingMaskIntoConstraints = NO;
  trackContainer.accessibilityLabel = @"Text size slider.";
  UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(fontSizePan:)];
  [trackContainer addGestureRecognizer:pan];

  self.fontSizeTrackView = [[UIView alloc] init];
  self.fontSizeTrackView.translatesAutoresizingMaskIntoConstraints = NO;
  self.fontSizeTrackView.layer.cornerRadius = 2.0;

  self.fontSizeTrackFillView = [[UIView alloc] init];
  self.fontSizeTrackFillView.translatesAutoresizingMaskIntoConstraints = NO;
  self.fontSizeTrackFillView.layer.cornerRadius = 2.0;

  [previewCard addSubview:self.fontSizePreviewLabel];
  [container addSubview:previewCard];
  [container addSubview:smallLabel];
  [container addSubview:trackContainer];
  [container addSubview:largeLabel];
  [trackContainer addSubview:self.fontSizeTrackView];
  [self.fontSizeTrackView addSubview:self.fontSizeTrackFillView];

  self.fontSizeTrackFillWidthConstraint = [self.fontSizeTrackFillView.widthAnchor constraintEqualToConstant:0.0];

  NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
  UIStackView *stopsStack = [[UIStackView alloc] init];
  stopsStack.translatesAutoresizingMaskIntoConstraints = NO;
  stopsStack.axis = UILayoutConstraintAxisHorizontal;
  stopsStack.distribution = UIStackViewDistributionEqualSpacing;
  stopsStack.alignment = UIStackViewAlignmentCenter;
  stopsStack.userInteractionEnabled = YES;
  [trackContainer addSubview:stopsStack];

  for (NSInteger index = 0; index < 5; index += 1) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.tag = NFBFontSizeStopBaseTag + index;
    button.layer.cornerRadius = 6.0;
    button.layer.borderWidth = 2.0;
    button.accessibilityLabel = @"Text size slider.";
    [button addTarget:self action:@selector(fontSizeStopTapped:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:button];
    [stopsStack addArrangedSubview:button];
    [buttons addObject:button];
    [NSLayoutConstraint activateConstraints:@[
      [button.widthAnchor constraintEqualToConstant:12.0],
      [button.heightAnchor constraintEqualToConstant:12.0]
    ]];
  }
  self.fontSizeStopButtons = buttons;

  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintGreaterThanOrEqualToConstant:176.0],
    [previewCard.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
    [previewCard.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
    [previewCard.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
    [self.fontSizePreviewLabel.topAnchor constraintEqualToAnchor:previewCard.topAnchor constant:13.0],
    [self.fontSizePreviewLabel.leadingAnchor constraintEqualToAnchor:previewCard.leadingAnchor constant:14.0],
    [self.fontSizePreviewLabel.trailingAnchor constraintEqualToAnchor:previewCard.trailingAnchor constant:-14.0],
    [self.fontSizePreviewLabel.bottomAnchor constraintEqualToAnchor:previewCard.bottomAnchor constant:-13.0],
    [smallLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
    [smallLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-20.0],
    [smallLabel.widthAnchor constraintEqualToConstant:30.0],
    [trackContainer.leadingAnchor constraintEqualToAnchor:smallLabel.trailingAnchor constant:14.0],
    [trackContainer.trailingAnchor constraintEqualToAnchor:largeLabel.leadingAnchor constant:-14.0],
    [trackContainer.centerYAnchor constraintEqualToAnchor:smallLabel.centerYAnchor],
    [trackContainer.heightAnchor constraintEqualToConstant:44.0],
    [largeLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
    [largeLabel.centerYAnchor constraintEqualToAnchor:smallLabel.centerYAnchor],
    [largeLabel.widthAnchor constraintEqualToConstant:42.0],
    [self.fontSizeTrackView.leadingAnchor constraintEqualToAnchor:trackContainer.leadingAnchor],
    [self.fontSizeTrackView.trailingAnchor constraintEqualToAnchor:trackContainer.trailingAnchor],
    [self.fontSizeTrackView.centerYAnchor constraintEqualToAnchor:trackContainer.centerYAnchor],
    [self.fontSizeTrackView.heightAnchor constraintEqualToConstant:4.0],
    [self.fontSizeTrackFillView.leadingAnchor constraintEqualToAnchor:self.fontSizeTrackView.leadingAnchor],
    [self.fontSizeTrackFillView.topAnchor constraintEqualToAnchor:self.fontSizeTrackView.topAnchor],
    [self.fontSizeTrackFillView.bottomAnchor constraintEqualToAnchor:self.fontSizeTrackView.bottomAnchor],
    self.fontSizeTrackFillWidthConstraint,
    [stopsStack.leadingAnchor constraintEqualToAnchor:trackContainer.leadingAnchor],
    [stopsStack.trailingAnchor constraintEqualToAnchor:trackContainer.trailingAnchor],
    [stopsStack.centerYAnchor constraintEqualToAnchor:trackContainer.centerYAnchor]
  ]];

  return container;
}

- (UIView *)displayModesView {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;

  UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
    [self displayModeControlWithTitle:@"Light" mode:NFBDisplayModeLight previewColor:UIColor.whiteColor],
    [self displayModeControlWithTitle:@"Dim" mode:NFBDisplayModeDim previewColor:[UIColor colorWithRed:0.082 green:0.125 blue:0.169 alpha:1.0]],
    [self displayModeControlWithTitle:@"Dark" mode:NFBDisplayModeDark previewColor:UIColor.blackColor]
  ]];
  stack.translatesAutoresizingMaskIntoConstraints = NO;
  stack.axis = UILayoutConstraintAxisHorizontal;
  stack.distribution = UIStackViewDistributionFillEqually;
  stack.spacing = 10.0;
  self.displayControls = (NSArray<UIControl *> *)stack.arrangedSubviews;

  [container addSubview:stack];
  [NSLayoutConstraint activateConstraints:@[
    [container.heightAnchor constraintEqualToConstant:142.0],
    [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:10.0],
    [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16.0],
    [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16.0],
    [stack.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-10.0]
  ]];
  return container;
}

- (UIControl *)displayModeControlWithTitle:(NSString *)title mode:(NSString *)mode previewColor:(UIColor *)previewColor {
  UIControl *control = [[UIControl alloc] init];
  control.translatesAutoresizingMaskIntoConstraints = NO;
  control.accessibilityIdentifier = mode;
  control.layer.cornerRadius = 12.0;
  control.layer.borderWidth = 2.0;
  control.clipsToBounds = NO;
  [control addTarget:self action:@selector(displayModeTapped:) forControlEvents:UIControlEventTouchUpInside];

  UIView *preview = [[UIView alloc] init];
  preview.translatesAutoresizingMaskIntoConstraints = NO;
  preview.tag = NFBDisplayModePreviewTag;
  preview.backgroundColor = previewColor;
  preview.layer.cornerRadius = 18.0;
  preview.layer.borderWidth = 1.0;

  UIView *previewLine = [[UIView alloc] init];
  previewLine.translatesAutoresizingMaskIntoConstraints = NO;
  previewLine.backgroundColor = NFBColorAccent();
  previewLine.layer.cornerRadius = 2.0;

  UILabel *label = [[UILabel alloc] init];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.tag = NFBDisplayModeTitleTag;
  label.text = title;
  label.font = NFBFont(14.0, NFBFontWeightBold);
  label.textAlignment = NSTextAlignmentCenter;

	  UIImageView *check = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_circle")];
  check.translatesAutoresizingMaskIntoConstraints = NO;
  check.tag = NFBDisplayModeCheckTag;
  check.contentMode = UIViewContentModeScaleAspectFit;

  [control addSubview:preview];
  [control addSubview:label];
  [control addSubview:check];
  [preview addSubview:previewLine];

  [NSLayoutConstraint activateConstraints:@[
    [preview.topAnchor constraintEqualToAnchor:control.topAnchor constant:12.0],
    [preview.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
    [preview.widthAnchor constraintEqualToConstant:54.0],
    [preview.heightAnchor constraintEqualToConstant:54.0],
    [previewLine.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor constant:10.0],
    [previewLine.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:-10.0],
    [previewLine.bottomAnchor constraintEqualToAnchor:preview.bottomAnchor constant:-12.0],
    [previewLine.heightAnchor constraintEqualToConstant:4.0],
    [label.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:8.0],
    [label.leadingAnchor constraintEqualToAnchor:control.leadingAnchor constant:4.0],
    [label.trailingAnchor constraintEqualToAnchor:control.trailingAnchor constant:-4.0],
    [check.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:4.0],
    [check.centerXAnchor constraintEqualToAnchor:control.centerXAnchor],
    [check.widthAnchor constraintEqualToConstant:22.0],
    [check.heightAnchor constraintEqualToConstant:22.0]
  ]];
  return control;
}

- (UIView *)standardSiteArticlesRowView {
  UIControl *row = [[UIControl alloc] init];
  self.standardSiteArticlesRowControl = row;
  row.translatesAutoresizingMaskIntoConstraints = NO;
  row.backgroundColor = NFBColorBackground();
  [row addTarget:self action:@selector(standardSiteArticlesRowTapped:) forControlEvents:UIControlEventTouchUpInside];

  UILabel *titleLabel = [[UILabel alloc] init];
  titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
  titleLabel.text = @"Inline Standard.site articles";
  titleLabel.font = NFBFont(16.0, NFBFontWeightRegular);
  titleLabel.textColor = NFBColorText();
  titleLabel.numberOfLines = 1;
  titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.standardSiteArticlesSwitch = [[UISwitch alloc] init];
  self.standardSiteArticlesSwitch.translatesAutoresizingMaskIntoConstraints = NO;
  self.standardSiteArticlesSwitch.on = NFBStandardSiteArticlesInline();
  self.standardSiteArticlesSwitch.onTintColor = NFBColorAccent();
  [self.standardSiteArticlesSwitch addTarget:self action:@selector(standardSiteArticlesSwitchChanged:) forControlEvents:UIControlEventValueChanged];

  UIView *border = [[UIView alloc] init];
  self.standardSiteArticlesBorder = border;
  border.translatesAutoresizingMaskIntoConstraints = NO;
  border.backgroundColor = NFBColorBorder();

  [row addSubview:titleLabel];
  [row addSubview:self.standardSiteArticlesSwitch];
  [row addSubview:border];

  [NSLayoutConstraint activateConstraints:@[
    [row.heightAnchor constraintEqualToConstant:56.0],
    [titleLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
    [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.standardSiteArticlesSwitch.leadingAnchor constant:-16.0],
    [titleLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [self.standardSiteArticlesSwitch.trailingAnchor constraintEqualToAnchor:row.trailingAnchor constant:-16.0],
    [self.standardSiteArticlesSwitch.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    [border.leadingAnchor constraintEqualToAnchor:row.leadingAnchor constant:16.0],
    [border.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
    [border.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    [border.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  return row;
}

- (UIView *)colorCollectionContainer {
  UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
  layout.sectionInset = UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
  layout.minimumLineSpacing = 10.0;
  layout.minimumInteritemSpacing = 10.0;

  self.colorCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
  self.colorCollectionView.translatesAutoresizingMaskIntoConstraints = NO;
  self.colorCollectionView.backgroundColor = NFBColorBackground();
  self.colorCollectionView.scrollEnabled = NO;
  self.colorCollectionView.dataSource = self;
  self.colorCollectionView.delegate = self;
  [self.colorCollectionView registerClass:NFBAccentColorCell.class forCellWithReuseIdentifier:@"accent"];

  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  [container addSubview:self.colorCollectionView];
  self.colorCollectionHeightConstraint = [self.colorCollectionView.heightAnchor constraintEqualToConstant:190.0];
  [NSLayoutConstraint activateConstraints:@[
    [self.colorCollectionView.topAnchor constraintEqualToAnchor:container.topAnchor],
    [self.colorCollectionView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [self.colorCollectionView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [self.colorCollectionView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    self.colorCollectionHeightConstraint
  ]];
  return container;
}

- (void)displayModeTapped:(UIControl *)sender {
  NFBSetDisplayMode(sender.accessibilityIdentifier ?: NFBDisplayModeDark);
}

- (void)fontSizeStopTapped:(UIButton *)sender {
  NFBSetFontSizeLevel(sender.tag - NFBFontSizeStopBaseTag);
}

- (void)fontSizePan:(UIPanGestureRecognizer *)gesture {
  UIView *view = gesture.view;
  if (!view) return;
  CGPoint location = [gesture locationInView:view];
  CGFloat width = MAX(1.0, CGRectGetWidth(view.bounds));
  CGFloat progress = MAX(0.0, MIN(1.0, location.x / width));
  NSInteger level = (NSInteger)lround(progress * 4.0);
  NFBSetFontSizeLevel(level);
}

- (void)updateFontSizeControls {
  NSInteger level = NFBCurrentFontSizeLevel();
  CGFloat progress = level / 4.0;
  CGFloat trackWidth = CGRectGetWidth(self.fontSizeTrackView.bounds);
  self.fontSizeTrackFillWidthConstraint.constant = trackWidth * progress;
  self.fontSizeTrackView.backgroundColor = NFBColorBorder();
  self.fontSizeTrackFillView.backgroundColor = NFBColorAccent();
  self.fontSizePreviewLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.fontSizePreviewLabel.textColor = NFBColorText();
  self.fontSizePreviewLabel.superview.backgroundColor = NFBColorBackground();
  self.fontSizePreviewLabel.superview.layer.borderColor = NFBColorBorder().CGColor;
  for (UIButton *button in self.fontSizeStopButtons) {
    NSInteger index = button.tag - NFBFontSizeStopBaseTag;
    BOOL selected = index <= level;
    button.backgroundColor = selected ? NFBColorAccent() : NFBColorBorder();
    button.layer.borderColor = NFBColorBackground().CGColor;
  }
}

- (void)standardSiteArticlesRowTapped:(UIControl *)sender {
  (void)sender;
  [self.standardSiteArticlesSwitch setOn:!self.standardSiteArticlesSwitch.isOn animated:YES];
  NFBSetStandardSiteArticlesInline(self.standardSiteArticlesSwitch.isOn);
}

- (void)standardSiteArticlesSwitchChanged:(UISwitch *)sender {
  NFBSetStandardSiteArticlesInline(sender.isOn);
}

- (void)closeTapped {
  if (self.navigationController.viewControllers.firstObject != self) {
    [self.navigationController popViewControllerAnimated:YES];
  } else if (self.navigationController.presentingViewController) {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
  }
}

- (void)configureNavigationButton {
  BOOL pushed = self.navigationController.viewControllers.firstObject != self;
  if (pushed) {
    self.navigationItem.leftBarButtonItem = NFBBackBarButtonItem(self, @selector(closeTapped));
  } else {
    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    closeButton.frame = CGRectMake(0.0, 0.0, 34.0, 34.0);
    [closeButton setImage:NFBTemplateIcon(@"nfb_close") forState:UIControlStateNormal];
    closeButton.tintColor = NFBColorText();
    [closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:closeButton];
  }
}

- (void)themeChanged:(NSNotification *)notification {
  (void)notification;
  [self refreshTheme];
}

- (void)refreshTheme {
  self.view.backgroundColor = NFBColorBackground();
  self.scrollView.backgroundColor = NFBColorBackground();
  [self updateStaticTextColorsInView:self.contentStack];
  self.headerLabel.textColor = NFBColorSecondaryText();
  self.colorCollectionView.backgroundColor = NFBColorBackground();
  self.navigationItem.leftBarButtonItem.customView.tintColor = NFBColorText();
  if ([self.navigationController isKindOfClass:UINavigationController.class]) {
    NFBApplyNavigationAppearance(self.navigationController);
  }
  [self updateDisplayControls];
  [self updateFontSizeControls];
  self.standardSiteArticlesSwitch.on = NFBStandardSiteArticlesInline();
  self.standardSiteArticlesSwitch.onTintColor = NFBColorAccent();
  self.standardSiteArticlesRowControl.backgroundColor = NFBColorBackground();
  self.standardSiteArticlesBorder.backgroundColor = NFBColorBorder();
  [self.colorCollectionView reloadData];
}

- (void)updateStaticTextColorsInView:(UIView *)view {
  if ([view isKindOfClass:UILabel.class] && view != self.headerLabel) {
    ((UILabel *)view).textColor = NFBColorText();
  }
  for (UIView *subview in view.subviews) {
    [self updateStaticTextColorsInView:subview];
  }
}

- (void)updateDisplayControls {
  NSString *currentMode = NFBCurrentDisplayMode();
  for (UIControl *control in self.displayControls) {
    BOOL selected = [control.accessibilityIdentifier isEqualToString:currentMode];
    control.backgroundColor = selected ? [NFBColorAccent() colorWithAlphaComponent:0.08] : NFBColorBackground();
    control.layer.borderColor = (selected ? NFBColorAccent() : NFBColorBorder()).CGColor;
    UILabel *label = [control viewWithTag:NFBDisplayModeTitleTag];
    label.textColor = selected ? NFBColorText() : NFBColorSecondaryText();
    UIImageView *check = [control viewWithTag:NFBDisplayModeCheckTag];
	    check.image = NFBTemplateIcon(selected ? @"nfb_checkmark_circle" : @"nfb_circle");
    check.tintColor = selected ? NFBColorAccent() : NFBColorSecondaryText();
    UIView *preview = [control viewWithTag:NFBDisplayModePreviewTag];
    preview.layer.borderColor = NFBColorBorder().CGColor;
    for (UIView *subview in preview.subviews) {
      subview.backgroundColor = NFBColorAccent();
    }
  }
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
  (void)collectionView;
  (void)section;
  return (NSInteger)self.colorItems.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
  NFBAccentColorCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"accent" forIndexPath:indexPath];
  NSDictionary *item = self.colorItems[(NSUInteger)indexPath.item];
  NSInteger colorID = [item[@"id"] integerValue];
  [cell configureWithColorID:colorID name:item[@"name"] selected:colorID == NFBCurrentAccentColorID()];
  return cell;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
  NSDictionary *item = self.colorItems[(NSUInteger)indexPath.item];
  NFBSetAccentColorID([item[@"id"] integerValue]);
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
  (void)collectionView;
  (void)layout;
  (void)indexPath;
  return CGSizeMake(98.0, 74.0);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(NSInteger)section {
  (void)collectionView;
  (void)layout;
  (void)section;
  return UIEdgeInsetsMake(16.0, 16.0, 16.0, 16.0);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
  (void)collectionView;
  (void)layout;
  (void)section;
  return 10.0;
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
  (void)collectionView;
  (void)layout;
  (void)section;
  return 10.0;
}

@end
