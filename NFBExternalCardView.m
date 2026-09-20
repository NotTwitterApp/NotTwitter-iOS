#import "NFBExternalCardView.h"

#import "NFBAtprotoClient.h"
#import "NFBTheme.h"
#import "NFBArticleReaderView.h"
#import "NFBLinkRouter.h"

@interface NFBExternalCardView ()

@property (nonatomic, copy, readwrite, nullable) NSDictionary *card;
@property (nonatomic, strong) UIStackView *outerStack;
@property (nonatomic, strong) UIView *imageContainer;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UIView *accentStrip;
@property (nonatomic, strong) UIView *textContainer;
@property (nonatomic, strong) UIStackView *textStack;
@property (nonatomic, strong) UIStackView *metaStack;
@property (nonatomic, strong) UIImageView *sourceIconView;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIStackView *titleStack;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIImageView *titleExternalIconView;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIView *readArticleContainer;
@property (nonatomic, strong) UIStackView *readArticleStack;
@property (nonatomic, strong) UILabel *readArticleLabel;
@property (nonatomic, strong) UIImageView *readArticleIconView;
@property (nonatomic, strong) UIView *articleSeparator;
@property (nonatomic, strong) UILabel *articleBodyLabel;
@property (nonatomic, strong) UIStackView *articleContentStack;
@property (nonatomic, strong) NSLayoutConstraint *imageHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sourceIconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *sourceIconHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleExternalIconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *titleExternalIconHeightConstraint;
@property (nonatomic, strong) NSLayoutConstraint *readArticleIconWidthConstraint;
@property (nonatomic, strong) NSLayoutConstraint *readArticleIconHeightConstraint;
@property (nonatomic, copy) NSString *imageURLString;
@property (nonatomic, copy) NSString *sourceIconURLString;
@property (nonatomic, copy) NSString *articleRequestKey;
@property (nonatomic, strong) NSMutableArray<NSLayoutConstraint *> *articleImageHeightConstraints;
@property (nonatomic, assign) BOOL compact;
@property (nonatomic, assign) BOOL hasImage;
@property (nonatomic, assign) BOOL standardSite;
@property (nonatomic, assign) BOOL inlineArticleReader;
@property (nonatomic, assign) BOOL standardSitePreviewReader;
@property (nonatomic, assign) BOOL fullArticleReader;
@property (nonatomic, strong) NFBArticleReaderView *richArticleReader;
@property (nonatomic, strong) NSTimer *articleRefreshTimer;
@property (nonatomic, assign) BOOL articleRefreshing;

@end

@implementation NFBExternalCardView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self buildSubviews];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshVisibleArticle) name:UIApplicationDidBecomeActiveNotification object:nil];
  }
  return self;
}

- (void)dealloc {
  [self.articleRefreshTimer invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  [self.articleRefreshTimer invalidate];
  self.articleRefreshTimer = nil;
  if (!self.window) return;
  __weak typeof(self) weakSelf = self;
  self.articleRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:60 repeats:YES block:^(NSTimer *timer) {
    [weakSelf refreshVisibleArticle];
  }];
  [self refreshVisibleArticle];
}

- (void)refreshVisibleArticle {
  if (!self.window || self.hidden || !self.fullArticleReader || self.articleRefreshing || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
  CGRect rect = [self convertRect:self.bounds toView:self.window];
  if (CGRectIntersectsRect(rect, self.window.bounds)) [self fetchStandardSiteArticleForCurrentCard];
}

- (void)showRichArticle:(NSDictionary *)article {
  if (!self.richArticleReader) {
    self.richArticleReader = [[NFBArticleReaderView alloc] initWithFrame:CGRectZero];
    __weak typeof(self) weakSelf = self;
    self.richArticleReader.heightDidChange = ^{ [weakSelf finishArticleContentLayout]; };
    self.richArticleReader.openURL = ^(NSURL *url) {
      UIResponder *responder = weakSelf;
      while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
      if (responder) NFBOpenTweetTextURL(url, (UIViewController *)responder);
    };
    [self.articleContentStack addArrangedSubview:self.richArticleReader];
  }
  [self.richArticleReader displayArticle:article];
  [self finishArticleContentLayout];
}

- (void)buildSubviews {
  NFBIPAApplyEmbeddedCardFrameAppearance(self);
  self.accessibilityTraits = UIAccessibilityTraitLink;
  [self addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];

  self.imageContainer = [[UIView alloc] init];
  self.imageContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.imageContainer.clipsToBounds = YES;
  self.imageContainer.backgroundColor = NFBColorElevatedBackground();

  self.imageView = [[UIImageView alloc] init];
  self.imageView.translatesAutoresizingMaskIntoConstraints = NO;
  self.imageView.contentMode = UIViewContentModeScaleAspectFill;
  self.imageView.clipsToBounds = YES;
  self.imageView.userInteractionEnabled = NO;
  [self.imageContainer addSubview:self.imageView];

  self.accentStrip = [[UIView alloc] init];
  self.accentStrip.translatesAutoresizingMaskIntoConstraints = NO;
  self.accentStrip.hidden = YES;
  self.accentStrip.userInteractionEnabled = NO;
  [self.imageContainer addSubview:self.accentStrip];

  self.textContainer = [[UIView alloc] init];
  self.textContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.textContainer.backgroundColor = NFBColorBackground();
  self.textContainer.userInteractionEnabled = NO;

  self.sourceIconView = [[UIImageView alloc] init];
  self.sourceIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.sourceIconView.image = NFBTemplateIcon(@"nfb_link");
  self.sourceIconView.contentMode = UIViewContentModeScaleAspectFit;
  self.sourceIconView.clipsToBounds = YES;
  self.sourceIconView.tintColor = NFBColorSecondaryText();
  self.sourceIconView.hidden = YES;

  self.metaLabel = [[UILabel alloc] init];
  self.metaLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  self.metaLabel.textColor = NFBColorSecondaryText();
  self.metaLabel.numberOfLines = 1;
  self.metaLabel.lineBreakMode = NSLineBreakByTruncatingTail;

  self.metaStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.sourceIconView, self.metaLabel]];
  self.metaStack.axis = UILayoutConstraintAxisHorizontal;
  self.metaStack.alignment = UIStackViewAlignmentCenter;
  self.metaStack.spacing = 5.0;
  self.metaStack.userInteractionEnabled = NO;

  self.titleLabel = [[UILabel alloc] init];
  self.titleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.titleLabel.textColor = NFBColorText();
  self.titleLabel.numberOfLines = 2;
  self.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
  [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

  self.titleExternalIconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_external_link")];
  self.titleExternalIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.titleExternalIconView.contentMode = UIViewContentModeScaleAspectFit;
  self.titleExternalIconView.tintColor = NFBColorAccent();
  self.titleExternalIconView.hidden = YES;
  [self.titleExternalIconView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.titleExternalIconView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.titleStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.titleLabel, self.titleExternalIconView]];
  self.titleStack.axis = UILayoutConstraintAxisHorizontal;
  self.titleStack.alignment = UIStackViewAlignmentFirstBaseline;
  self.titleStack.spacing = 5.0;
  self.titleStack.userInteractionEnabled = NO;

  self.descriptionLabel = [[UILabel alloc] init];
  self.descriptionLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.descriptionLabel.textColor = NFBColorSecondaryText();
  self.descriptionLabel.numberOfLines = 2;
  self.descriptionLabel.lineBreakMode = NSLineBreakByTruncatingTail;
  [self.descriptionLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

  self.readArticleLabel = [[UILabel alloc] init];
  self.readArticleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.readArticleLabel.textColor = NFBColorAccent();
  self.readArticleLabel.text = @"Read on website";
  self.readArticleLabel.numberOfLines = 1;
  [self.readArticleLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.readArticleLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.readArticleIconView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_external_link")];
  self.readArticleIconView.translatesAutoresizingMaskIntoConstraints = NO;
  self.readArticleIconView.contentMode = UIViewContentModeScaleAspectFit;
  self.readArticleIconView.tintColor = NFBColorAccent();

  self.readArticleStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.readArticleLabel, self.readArticleIconView]];
  self.readArticleStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.readArticleStack.axis = UILayoutConstraintAxisHorizontal;
  self.readArticleStack.alignment = UIStackViewAlignmentCenter;
  self.readArticleStack.spacing = 4.0;
  self.readArticleStack.userInteractionEnabled = NO;
  [self.readArticleStack setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
  [self.readArticleStack setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

  self.readArticleContainer = [[UIView alloc] init];
  self.readArticleContainer.translatesAutoresizingMaskIntoConstraints = NO;
  self.readArticleContainer.hidden = YES;
  self.readArticleContainer.userInteractionEnabled = YES;
  [self.readArticleContainer addSubview:self.readArticleStack];
  UITapGestureRecognizer *readArticleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(readArticleTapped:)];
  readArticleTap.cancelsTouchesInView = YES;
  [self.readArticleContainer addGestureRecognizer:readArticleTap];

  self.articleSeparator = [[UIView alloc] init];
  self.articleSeparator.translatesAutoresizingMaskIntoConstraints = NO;
  self.articleSeparator.backgroundColor = NFBColorBorder();
  self.articleSeparator.hidden = YES;

  self.articleBodyLabel = [[UILabel alloc] init];
  self.articleBodyLabel.font = NFBFont(17.0, NFBFontWeightRegular);
  self.articleBodyLabel.textColor = NFBColorText();
  self.articleBodyLabel.numberOfLines = 0;
  self.articleBodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
  self.articleBodyLabel.hidden = YES;

  self.articleContentStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.articleBodyLabel]];
  self.articleContentStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.articleContentStack.axis = UILayoutConstraintAxisVertical;
  self.articleContentStack.alignment = UIStackViewAlignmentFill;
  self.articleContentStack.spacing = 12.0;
  self.articleContentStack.hidden = YES;
  self.articleContentStack.userInteractionEnabled = NO;

  self.textStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.metaStack, self.titleStack, self.descriptionLabel, self.readArticleContainer, self.articleSeparator, self.articleContentStack]];
  self.textStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.textStack.axis = UILayoutConstraintAxisVertical;
  self.textStack.alignment = UIStackViewAlignmentFill;
  self.textStack.spacing = 2.0;
  self.textStack.userInteractionEnabled = NO;
  [self.textStack setCustomSpacing:3.0 afterView:self.titleStack];
  [self.textStack setCustomSpacing:5.0 afterView:self.descriptionLabel];
  [self.textStack setCustomSpacing:10.0 afterView:self.readArticleContainer];
  [self.textStack setCustomSpacing:9.0 afterView:self.articleSeparator];
  [self.textContainer addSubview:self.textStack];

  self.outerStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.imageContainer, self.textContainer]];
  self.outerStack.translatesAutoresizingMaskIntoConstraints = NO;
  self.outerStack.axis = UILayoutConstraintAxisVertical;
  self.outerStack.alignment = UIStackViewAlignmentFill;
  self.outerStack.spacing = 0.0;
  self.outerStack.userInteractionEnabled = NO;
  [self addSubview:self.outerStack];

  self.imageHeightConstraint = [self.imageContainer.heightAnchor constraintEqualToConstant:142.0];
  self.sourceIconWidthConstraint = [self.sourceIconView.widthAnchor constraintEqualToConstant:14.0];
  self.sourceIconHeightConstraint = [self.sourceIconView.heightAnchor constraintEqualToConstant:14.0];
  self.titleExternalIconWidthConstraint = [self.titleExternalIconView.widthAnchor constraintEqualToConstant:15.0];
  self.titleExternalIconHeightConstraint = [self.titleExternalIconView.heightAnchor constraintEqualToConstant:15.0];
  self.readArticleIconWidthConstraint = [self.readArticleIconView.widthAnchor constraintEqualToConstant:15.0];
  self.readArticleIconHeightConstraint = [self.readArticleIconView.heightAnchor constraintEqualToConstant:15.0];
  self.articleImageHeightConstraints = [NSMutableArray array];

  [NSLayoutConstraint activateConstraints:@[
    [self.outerStack.topAnchor constraintEqualToAnchor:self.topAnchor],
    [self.outerStack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [self.outerStack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [self.outerStack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [self.imageView.topAnchor constraintEqualToAnchor:self.imageContainer.topAnchor],
    [self.imageView.leadingAnchor constraintEqualToAnchor:self.imageContainer.leadingAnchor],
    [self.imageView.trailingAnchor constraintEqualToAnchor:self.imageContainer.trailingAnchor],
    [self.imageView.bottomAnchor constraintEqualToAnchor:self.imageContainer.bottomAnchor],
    [self.accentStrip.topAnchor constraintEqualToAnchor:self.imageContainer.topAnchor],
    [self.accentStrip.leadingAnchor constraintEqualToAnchor:self.imageContainer.leadingAnchor],
    [self.accentStrip.trailingAnchor constraintEqualToAnchor:self.imageContainer.trailingAnchor],
    [self.accentStrip.heightAnchor constraintEqualToConstant:2.0],
    [self.textStack.topAnchor constraintEqualToAnchor:self.textContainer.topAnchor constant:9.0],
    [self.textStack.leadingAnchor constraintEqualToAnchor:self.textContainer.leadingAnchor constant:12.0],
    [self.textStack.trailingAnchor constraintEqualToAnchor:self.textContainer.trailingAnchor constant:-12.0],
    [self.textStack.bottomAnchor constraintLessThanOrEqualToAnchor:self.textContainer.bottomAnchor constant:-9.0],
    [self.readArticleStack.topAnchor constraintEqualToAnchor:self.readArticleContainer.topAnchor],
    [self.readArticleStack.leadingAnchor constraintEqualToAnchor:self.readArticleContainer.leadingAnchor],
    [self.readArticleStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.readArticleContainer.trailingAnchor],
    [self.readArticleStack.bottomAnchor constraintEqualToAnchor:self.readArticleContainer.bottomAnchor],
    self.imageHeightConstraint,
    self.sourceIconWidthConstraint,
    self.sourceIconHeightConstraint,
    self.titleExternalIconWidthConstraint,
    self.titleExternalIconHeightConstraint,
    self.readArticleIconWidthConstraint,
    self.readArticleIconHeightConstraint,
    [self.articleSeparator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale]
  ]];
  [self applyTheme];
}

- (CGSize)intrinsicContentSize {
  if (!self.card) return CGSizeMake(UIViewNoIntrinsicMetric, 0.0);
  CGFloat width = CGRectGetWidth(self.bounds);
  return CGSizeMake(UIViewNoIntrinsicMetric, [self preferredHeightForWidth:width]);
}

- (CGFloat)preferredHeightForWidth:(CGFloat)width {
  if (!self.card) return 0.0;
  if (self.compact) return [self compactPreferredHeightForWidth:width];
  if (!self.fullArticleReader && !self.inlineArticleReader && !self.standardSitePreviewReader) {
    return self.hasImage ? (self.fullArticleReader ? 288.0 : 242.0) : 98.0;
  }

  CGFloat availableWidth = width > 0.0 ? width : CGRectGetWidth(UIScreen.mainScreen.bounds) - 92.0;
  CGFloat textWidth = MAX(1.0, availableWidth - 24.0);
  CGFloat height = 20.0;
  if (self.hasImage) {
    CGFloat imageHeight = floor(availableWidth * (630.0 / 1200.0));
    height += MAX(140.0, MIN(190.0, imageHeight));
  }

  CGFloat textHeight = 0.0;
  BOOL hasPrevious = NO;
  textHeight += [self appendMeasuredHeightForView:self.metaStack width:textWidth hasPrevious:&hasPrevious spacing:3.0];
  CGFloat titleWidth = self.titleExternalIconView.hidden ? textWidth : MAX(1.0, textWidth - 20.0);
  CGFloat titleHeight = [self measuredHeightForLabel:self.titleLabel width:titleWidth];
  if (titleHeight > 0.0) {
    if (hasPrevious) textHeight += 3.0;
    textHeight += MAX(titleHeight, self.titleExternalIconView.hidden ? 0.0 : 16.0);
    hasPrevious = YES;
  }
  textHeight += [self appendMeasuredHeightForView:self.descriptionLabel width:textWidth hasPrevious:&hasPrevious spacing:3.0];
  textHeight += [self appendMeasuredHeightForView:self.readArticleContainer width:textWidth hasPrevious:&hasPrevious spacing:6.0];
  if (!self.articleSeparator.hidden) {
    if (hasPrevious) textHeight += 10.0;
    textHeight += 1.0 / UIScreen.mainScreen.scale;
    hasPrevious = YES;
  }
  if (!self.articleContentStack.hidden && self.articleContentStack.arrangedSubviews.count > 0) {
    if (hasPrevious) textHeight += 9.0;
    textHeight += [self measuredHeightForArticleContentWidth:textWidth];
  }

  return ceil(height + textHeight);
}

- (CGFloat)compactImageHeightForWidth:(CGFloat)width {
  CGFloat targetWidth = width > 0.0 ? width : CGRectGetWidth(UIScreen.mainScreen.bounds) - 112.0;
  return ceil(MAX(84.0, MIN(116.0, targetWidth * 0.32)));
}

- (CGFloat)compactPreferredHeightForWidth:(CGFloat)width {
  CGFloat availableWidth = width > 0.0 ? width : CGRectGetWidth(UIScreen.mainScreen.bounds) - 112.0;
  CGFloat textWidth = MAX(1.0, availableWidth - 24.0);
  CGFloat textHeight = 0.0;
  BOOL hasPrevious = NO;
  textHeight += [self appendMeasuredHeightForView:self.metaStack width:textWidth hasPrevious:&hasPrevious spacing:3.0];
  CGFloat titleWidth = self.titleExternalIconView.hidden ? textWidth : MAX(1.0, textWidth - 20.0);
  CGFloat titleHeight = [self measuredHeightForLabel:self.titleLabel width:titleWidth];
  if (titleHeight > 0.0) {
    if (hasPrevious) textHeight += 3.0;
    textHeight += MAX(titleHeight, self.titleExternalIconView.hidden ? 0.0 : 15.0);
    hasPrevious = YES;
  }
  textHeight += [self appendMeasuredHeightForView:self.descriptionLabel width:textWidth hasPrevious:&hasPrevious spacing:5.0];
  CGFloat textContainerHeight = textHeight > 0.0 ? textHeight + 20.0 : 0.0;
  CGFloat imageHeight = self.hasImage ? [self compactImageHeightForWidth:availableWidth] : 0.0;
  CGFloat measuredHeight = imageHeight + textContainerHeight;
  return ceil(MAX(self.hasImage ? 164.0 : 90.0, measuredHeight));
}

- (CGFloat)measuredHeightForArticleContentWidth:(CGFloat)width {
  CGFloat height = 0.0;
  BOOL hasPrevious = NO;
  for (UIView *view in self.articleContentStack.arrangedSubviews) {
    if (view.hidden) continue;
    CGFloat viewHeight = 0.0;
    if ([view isKindOfClass:UILabel.class]) {
      viewHeight = [self measuredHeightForLabel:(UILabel *)view width:width];
    } else if ([view isKindOfClass:NFBArticleReaderView.class]) {
      viewHeight = [(NFBArticleReaderView *)view contentHeight];
    } else if (view.tag == 1901) {
      viewHeight = [self articleImageHeightForWidth:width];
    }
    if (viewHeight <= 0.0) continue;
    if (hasPrevious) height += self.articleContentStack.spacing;
    height += viewHeight;
    hasPrevious = YES;
  }
  return height;
}

- (CGFloat)appendMeasuredHeightForView:(UIView *)view width:(CGFloat)width hasPrevious:(BOOL *)hasPrevious spacing:(CGFloat)spacing {
  if (view.hidden) return 0.0;
  CGFloat height = 0.0;
  if ([view isKindOfClass:UILabel.class]) {
    height = [self measuredHeightForLabel:(UILabel *)view width:width];
  } else if (view == self.metaStack) {
    height = self.metaLabel.text.length > 0 ? ceil(self.metaLabel.font.lineHeight) : 0.0;
  } else if (view == self.readArticleContainer) {
    height = self.readArticleLabel.text.length > 0 ? ceil(MAX(self.readArticleLabel.font.lineHeight, 15.0)) : 0.0;
  }
  if (height <= 0.0) return 0.0;
  CGFloat total = (*hasPrevious ? spacing : 0.0) + height;
  *hasPrevious = YES;
  return total;
}

- (CGFloat)measuredHeightForLabel:(UILabel *)label width:(CGFloat)width {
  if (label.hidden || label.text.length == 0) return 0.0;
  CGSize size = [label sizeThatFits:CGSizeMake(MAX(1.0, width), CGFLOAT_MAX)];
  CGFloat height = ceil(size.height);
  if (label.numberOfLines > 0) height = MIN(height, ceil(label.font.lineHeight * label.numberOfLines));
  return height;
}

- (NSString *)readingTimeTextWithArticleText:(NSString *)articleText {
  NSInteger minutes = [self.card[@"readingTime"] respondsToSelector:@selector(integerValue)] ? [self.card[@"readingTime"] integerValue] : 0;
  if (minutes <= 0 && articleText.length > 0) {
    __block NSUInteger wordCount = 0;
    [articleText enumerateSubstringsInRange:NSMakeRange(0, articleText.length)
                                    options:NSStringEnumerationByWords
                                 usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
      (void)substring;
      (void)substringRange;
      (void)enclosingRange;
      (void)stop;
      wordCount++;
    }];
    if (wordCount > 0) minutes = MAX(1, (NSInteger)((wordCount + 224) / 225));
  }
  return minutes > 0 ? [NSString stringWithFormat:@"%ldm read", (long)minutes] : @"";
}

- (NSString *)titleTextForTitle:(NSString *)title articleText:(NSString *)articleText {
  NSString *cleanTitle = [title isKindOfClass:NSString.class] ? title : @"";
  if (!self.standardSite || cleanTitle.length == 0) return cleanTitle;
  NSString *readingTimeText = [self readingTimeTextWithArticleText:articleText];
  if (readingTimeText.length == 0 || [cleanTitle rangeOfString:readingTimeText].location != NSNotFound) return cleanTitle;
  return [NSString stringWithFormat:@"%@ · %@", cleanTitle, readingTimeText];
}

- (CGFloat)articleImageHeightForWidth:(CGFloat)width {
  CGFloat targetWidth = MAX(1.0, width);
  return ceil(MAX(160.0, MIN(440.0, targetWidth * 0.64)));
}

- (void)layoutSubviews {
  [super layoutSubviews];
  if (self.hasImage && self.compact) {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width > 0.0) {
      self.imageHeightConstraint.constant = [self compactImageHeightForWidth:width];
    }
  } else if (self.hasImage && !self.compact) {
    CGFloat width = CGRectGetWidth(self.bounds);
    if (width > 0.0) {
      CGFloat imageHeight = floor(width * (630.0 / 1200.0));
      self.imageHeightConstraint.constant = MAX(132.0, MIN(176.0, imageHeight));
    }
  }
  [self updateArticleImageHeights];
}

- (void)updateArticleImageHeights {
  if (self.articleImageHeightConstraints.count == 0) return;
  CGFloat width = CGRectGetWidth(self.articleContentStack.bounds);
  if (width <= 0.0) width = CGRectGetWidth(self.bounds) - 24.0;
  CGFloat height = [self articleImageHeightForWidth:width];
  for (NSLayoutConstraint *constraint in self.articleImageHeightConstraints) {
    constraint.constant = height;
  }
}

- (void)setHighlighted:(BOOL)highlighted {
  [super setHighlighted:highlighted];
  CGFloat alpha = highlighted ? 0.82 : 1.0;
  self.imageContainer.alpha = alpha;
  self.textContainer.alpha = alpha;
}

- (void)configureWithCard:(NSDictionary *)card {
  [self configureWithCard:card compact:NO fullArticleReader:NO];
}

- (void)configureWithCard:(NSDictionary *)card compact:(BOOL)compact {
  [self configureWithCard:card compact:compact fullArticleReader:NO];
}

- (void)configureWithCard:(NSDictionary *)card compact:(BOOL)compact fullArticleReader:(BOOL)fullArticleReader {
  self.card = [card isKindOfClass:NSDictionary.class] ? card : nil;
  self.compact = compact;
  self.fullArticleReader = NO;
  self.inlineArticleReader = NO;
  self.standardSitePreviewReader = NO;
  self.articleRequestKey = nil;
  self.articleRefreshing = NO;
  self.richArticleReader = nil;
  [self resetArticleContentViews];
  self.articleSeparator.hidden = YES;
  self.readArticleContainer.hidden = YES;
  self.titleExternalIconView.hidden = YES;
  self.hidden = self.card.count == 0;
  if (self.hidden) {
    self.imageURLString = nil;
    self.sourceIconURLString = nil;
    self.imageView.image = nil;
    self.sourceIconView.image = nil;
    self.articleRequestKey = nil;
    [self invalidateIntrinsicContentSize];
    return;
  }

  NSString *url = [self stringFromValue:self.card[@"url"]];
  NSString *title = [self stringFromValue:self.card[@"title"]];
  NSString *descriptionText = [self stringFromValue:self.card[@"description"]];
  NSString *domain = [self stringFromValue:self.card[@"domain"]];
  self.standardSite = [NFBAtprotoClient externalCardIsStandardSiteArticle:self.card];
  self.fullArticleReader = fullArticleReader && self.standardSite;
  self.outerStack.userInteractionEnabled = self.fullArticleReader;
  self.textContainer.userInteractionEnabled = self.fullArticleReader;
  self.textStack.userInteractionEnabled = self.fullArticleReader;
  self.articleContentStack.userInteractionEnabled = self.fullArticleReader;
  self.inlineArticleReader = NO;
  self.standardSitePreviewReader = NO;
  if (title.length == 0) title = url;
  if ([descriptionText isEqualToString:title] || [descriptionText isEqualToString:url]) descriptionText = @"";
  self.titleLabel.text = [self titleTextForTitle:title articleText:nil];
  self.descriptionLabel.text = descriptionText;
  self.descriptionLabel.hidden = descriptionText.length == 0;
  self.descriptionLabel.numberOfLines = compact ? 1 : 2;
  self.titleLabel.numberOfLines = 2;
  self.titleLabel.font = NFBFont(compact ? 14.0 : 15.0, NFBFontWeightRegular);
  self.descriptionLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.readArticleContainer.hidden = !(self.inlineArticleReader || self.fullArticleReader);

  NSDictionary *source = [self.card[@"source"] isKindOfClass:NSDictionary.class] ? self.card[@"source"] : nil;
  NSString *sourceTitle = [self stringFromValue:source[@"title"]];
  NSString *metaText = [self metaTextWithDomain:domain sourceTitle:sourceTitle url:url];
  self.metaLabel.text = metaText;
  self.metaStack.hidden = metaText.length == 0;

  self.hasImage = [self stringFromValue:self.card[@"thumbnailURL"]].length > 0;
  self.imageContainer.hidden = !self.hasImage;
  self.imageHeightConstraint.constant = self.hasImage ? (compact ? [self compactImageHeightForWidth:CGRectGetWidth(self.bounds)] : 154.0) : 0.0;
  if (self.hasImage) {
    [self loadImageURL:[self stringFromValue:self.card[@"thumbnailURL"]] intoImageView:self.imageView icon:NO];
  } else {
    self.imageURLString = nil;
    self.imageView.image = nil;
  }

  BOOL showSourceIcon = metaText.length > 0;
  self.sourceIconView.hidden = !showSourceIcon;
  self.sourceIconWidthConstraint.constant = showSourceIcon ? (compact ? 13.0 : 14.0) : 0.0;
  self.sourceIconHeightConstraint.constant = showSourceIcon ? (compact ? 13.0 : 14.0) : 0.0;
  self.sourceIconURLString = nil;
  self.sourceIconView.image = showSourceIcon ? NFBTemplateIcon(@"nfb_link") : nil;

  self.accentStrip.hidden = YES;
  self.accessibilityLabel = title;
  [self applyTheme];
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout];

  if (self.fullArticleReader) [self showRichArticle:self.card];
  if (self.fullArticleReader || self.inlineArticleReader || self.standardSitePreviewReader) {
    [self fetchStandardSiteArticleForCurrentCard];
  }
}

- (NSString *)articleIdentityKeyForCard:(NSDictionary *)card {
  if (![card isKindOfClass:NSDictionary.class]) return @"";
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  NSString *url = [self stringFromValue:card[@"url"]];
  if (url.length > 0) [parts addObject:url];
  NSArray *refs = [card[@"associatedRefs"] isKindOfClass:NSArray.class] ? card[@"associatedRefs"] : @[];
  for (NSDictionary *ref in refs) {
    if (![ref isKindOfClass:NSDictionary.class]) continue;
    NSString *uri = [self stringFromValue:ref[@"uri"]];
    if (uri.length > 0) [parts addObject:uri];
  }
  return [parts componentsJoinedByString:@"|"];
}

- (void)fetchStandardSiteArticleForCurrentCard {
  NSString *requestKey = [self articleIdentityKeyForCard:self.card];
  if (requestKey.length == 0) return;
  if (self.articleRefreshing) return;
  self.articleRefreshing = YES;
  // A new nonce also rejects stale responses after a reused view returns to the same URL.
  requestKey = [requestKey stringByAppendingString:NSUUID.UUID.UUIDString];
  self.articleRequestKey = requestKey;
  NSDictionary *currentCard = self.card;
  __weak typeof(self) weakSelf = self;
  [[NFBAtprotoClient sharedClient] fetchStandardSiteArticleForCard:currentCard completion:^(NSDictionary *article, NSError *error) {
    (void)error;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf.articleRequestKey isEqualToString:requestKey]) return;
      strongSelf.articleRefreshing = NO;
      if (article.count == 0) { [strongSelf.richArticleReader refresh]; return; }
      [strongSelf applyStandardSiteArticle:article];
    });
  }];
}

- (void)applyStandardSiteArticle:(NSDictionary *)article {
  NSString *title = [self stringFromValue:article[@"title"]];
  NSString *descriptionText = [self stringFromValue:article[@"description"]];
  NSString *textContent = [self stringFromValue:article[@"textContent"]];
  NSString *resolvedTitle = title.length > 0 ? title : [self stringFromValue:self.card[@"title"]];
  if (resolvedTitle.length > 0) self.titleLabel.text = [self titleTextForTitle:resolvedTitle articleText:textContent];
  if (descriptionText.length > 0 && ![descriptionText isEqualToString:resolvedTitle]) {
    self.descriptionLabel.text = descriptionText;
    self.descriptionLabel.hidden = NO;
  }

  if (self.fullArticleReader) {
    [self showRichArticle:article];
    return;
  }
  NSString *body = [self articleBodyTextFromContent:textContent];
  [self resetArticleContentViews];
  NSArray<NSDictionary *> *blocks = @[];
  if (self.fullArticleReader) {
    blocks = [self articleBlocksForArticle:article fallbackText:body];
    [self renderArticleBlocks:blocks article:article];
  } else if ((self.inlineArticleReader || self.standardSitePreviewReader) && body.length > 0) {
    NSString *preview = [NFBAtprotoClient standardSiteArticleExcerptFromText:body maxLength:220];
    if (preview.length > 0) {
      self.descriptionLabel.attributedText = [self attributedTextForMarkdownInlineText:preview font:self.descriptionLabel.font textColor:NFBColorSecondaryText()];
      self.descriptionLabel.hidden = NO;
      self.descriptionLabel.numberOfLines = 4;
    }
  }
  self.accessibilityLabel = title.length > 0 ? title : self.accessibilityLabel;
  [self finishArticleContentLayout];

  if (self.fullArticleReader && ![self articleBlocksContainRichFormatting:blocks]) {
    [self fetchCanonicalHTMLArticleBlocksForArticle:article requestKey:self.articleRequestKey];
  } else if (!self.fullArticleReader && body.length == 0 && (self.inlineArticleReader || self.standardSitePreviewReader)) {
    [self fetchCanonicalHTMLArticleBlocksForArticle:article requestKey:self.articleRequestKey];
  }
}

- (void)finishArticleContentLayout {
  self.articleContentStack.hidden = self.articleContentStack.arrangedSubviews.count == 0;
  self.articleSeparator.hidden = self.articleContentStack.hidden;
  [self updateArticleImageHeights];
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout];
  if ([self.delegate respondsToSelector:@selector(externalCardViewDidUpdateContent:)]) {
    [self.delegate externalCardViewDidUpdateContent:self];
  }
}

- (BOOL)articleBlocksContainRichFormatting:(NSArray<NSDictionary *> *)blocks {
  for (NSDictionary *block in blocks) {
    NSString *type = [self stringFromValue:block[@"type"]];
    if ([type isEqualToString:@"heading"] || [type isEqualToString:@"image"] || [type isEqualToString:@"blockquote"] || [type isEqualToString:@"code"]) return YES;
  }
  return NO;
}

- (void)fetchCanonicalHTMLArticleBlocksForArticle:(NSDictionary *)article requestKey:(NSString *)requestKey {
  if (requestKey.length == 0) return;
  NSString *urlString = [self stringFromValue:article[@"url"]];
  if (urlString.length == 0) return;
  NSURL *url = [NSURL URLWithString:urlString];
  if (!url || !url.scheme.length || !url.host.length) return;
  if (![[url.scheme lowercaseString] isEqualToString:@"http"] && ![[url.scheme lowercaseString] isEqualToString:@"https"]) return;

  NSArray<NSDictionary *> *cachedBlocks = [[self.class articleHTMLBlockCache] objectForKey:url.absoluteString];
  if (cachedBlocks.count > 0) {
    [self applyCanonicalHTMLArticleBlocks:cachedBlocks article:article requestKey:requestKey];
    return;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:14.0];
  [request setValue:@"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];
  __weak typeof(self) weakSelf = self;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (html.length == 0) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (html.length == 0) return;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf.articleRequestKey isEqualToString:requestKey]) return;
      NSArray<NSDictionary *> *blocks = [strongSelf blocksFromHTML:html articleTitle:[strongSelf stringFromValue:article[@"title"]] baseURL:url];
      if (blocks.count == 0) return;
      [[strongSelf.class articleHTMLBlockCache] setObject:blocks forKey:url.absoluteString];
      [strongSelf applyCanonicalHTMLArticleBlocks:blocks article:article requestKey:requestKey];
    });
  }];
  [task resume];
}

- (void)applyCanonicalHTMLArticleBlocks:(NSArray<NSDictionary *> *)blocks article:(NSDictionary *)article requestKey:(NSString *)requestKey {
  if (blocks.count == 0 || ![self.articleRequestKey isEqualToString:requestKey]) return;
  [self resetArticleContentViews];
  if (self.fullArticleReader) {
    [self renderArticleBlocks:blocks article:article];
  } else {
    NSString *preview = [NFBAtprotoClient standardSiteArticleExcerptFromText:[self articleTextFromBlocks:blocks] maxLength:220];
    if (preview.length > 0) {
      self.descriptionLabel.attributedText = [self attributedTextForMarkdownInlineText:preview font:self.descriptionLabel.font textColor:NFBColorSecondaryText()];
      self.descriptionLabel.hidden = NO;
      self.descriptionLabel.numberOfLines = 4;
    }
  }
  [self finishArticleContentLayout];
}

- (NSString *)articleBodyTextFromContent:(NSString *)textContent {
  textContent = [self articleTextByRemovingReaderPreamble:textContent];
  if (textContent.length == 0) return @"";
  if (!self.fullArticleReader) {
    return [NFBAtprotoClient standardSiteArticleExcerptFromText:textContent maxLength:220];
  }
  NSArray<NSString *> *paragraphs = [textContent componentsSeparatedByString:@"\n\n"];
  NSMutableArray<NSString *> *cleanParagraphs = [NSMutableArray array];
  for (NSString *paragraph in paragraphs) {
    NSString *clean = [[paragraph stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (clean.length > 0) [cleanParagraphs addObject:clean];
  }
  return [cleanParagraphs componentsJoinedByString:@"\n\n"];
}

- (NSString *)articleTextFromBlocks:(NSArray<NSDictionary *> *)blocks {
  NSMutableArray<NSString *> *parts = [NSMutableArray array];
  for (NSDictionary *block in blocks) {
    if (![block isKindOfClass:NSDictionary.class]) continue;
    NSString *text = [self stringFromValue:block[@"text"]];
    if (text.length > 0) [parts addObject:text];
  }
  return [parts componentsJoinedByString:@"\n\n"];
}

- (NSString *)articleTextByRemovingReaderPreamble:(NSString *)text {
  if (![text isKindOfClass:NSString.class] || text.length == 0) return @"";
  NSString *normalized = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
  NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
  NSUInteger scanLimit = MIN(lines.count, (NSUInteger)12);
  BOOL sawTitle = NO;
  BOOL sawURLSource = NO;

  for (NSUInteger index = 0; index < scanLimit; index++) {
    NSString *line = [lines[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([self string:line matchesRegex:@"(?i)^title:\\s+"]) sawTitle = YES;
    if ([self string:line matchesRegex:@"(?i)^url source:\\s+"]) sawURLSource = YES;
    if ([self string:line matchesRegex:@"(?i)^markdown content:\\s*$"] && sawTitle && sawURLSource) {
      NSArray<NSString *> *bodyLines = index + 1 < lines.count ? [lines subarrayWithRange:NSMakeRange(index + 1, lines.count - index - 1)] : @[];
      NSString *body = [bodyLines componentsJoinedByString:@"\n"];
      return [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
  }

  return [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (void)resetArticleContentViews {
  NSArray<UIView *> *views = [self.articleContentStack.arrangedSubviews copy] ?: @[];
  for (UIView *view in views) {
    [self.articleContentStack removeArrangedSubview:view];
    [view removeFromSuperview];
  }
  self.articleBodyLabel = [self articleTextLabelWithFont:NFBFont(17.0, NFBFontWeightRegular) textColor:NFBColorText()];
  self.articleBodyLabel.hidden = YES;
  self.articleContentStack.hidden = YES;
  [self.articleImageHeightConstraints removeAllObjects];
}

- (NSArray<NSDictionary *> *)articleBlocksForArticle:(NSDictionary *)article fallbackText:(NSString *)fallbackText {
  id content = article[@"content"];
  NSArray<NSDictionary *> *blocks = [self blocksFromLeafletContent:content];
  if (blocks.count > 0) return blocks;

  NSString *markdown = [self markdownTextFromContent:content];
  if (markdown.length > 0) {
    blocks = [self blocksFromMarkdown:markdown articleTitle:[self stringFromValue:article[@"title"]]];
    if (blocks.count > 0) return blocks;
  }

  NSString *html = [self htmlTextFromContent:content];
  if (html.length > 0) {
    NSURL *baseURL = [NSURL URLWithString:[self stringFromValue:article[@"url"]]];
    blocks = [self blocksFromHTML:html articleTitle:[self stringFromValue:article[@"title"]] baseURL:baseURL];
    if (blocks.count > 0) return blocks;
  }

  NSMutableArray<NSDictionary *> *paragraphs = [NSMutableArray array];
  for (NSString *paragraph in [fallbackText componentsSeparatedByString:@"\n\n"]) {
    NSString *clean = [paragraph stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (clean.length > 0) [paragraphs addObject:@{@"type": @"paragraph", @"text": clean}];
  }
  return [paragraphs copy];
}

- (NSString *)markdownTextFromContent:(id)content {
  if ([content isKindOfClass:NSString.class]) return (NSString *)content;
  if (![content isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *dictionary = (NSDictionary *)content;
  NSString *type = [self stringFromValue:dictionary[@"$type"]].lowercaseString;
  BOOL markdownType = [type rangeOfString:@"markdown"].location != NSNotFound;
  for (NSString *key in @[@"text", @"markdown", @"content", @"value"]) {
    NSString *value = [self stringFromValue:dictionary[key]];
    if (value.length > 0 && (markdownType || [self stringLooksLikeMarkdown:value])) return value;
  }
  return @"";
}

- (NSString *)htmlTextFromContent:(id)content {
  if (![content isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *dictionary = (NSDictionary *)content;
  NSString *type = [self stringFromValue:dictionary[@"$type"]].lowercaseString;
  if ([type rangeOfString:@"html"].location == NSNotFound) return @"";
  for (NSString *key in @[@"text", @"html", @"content", @"value"]) {
    NSString *value = [self stringFromValue:dictionary[key]];
    if (value.length > 0) return value;
  }
  return @"";
}

- (BOOL)stringLooksLikeMarkdown:(NSString *)text {
  if (text.length == 0) return NO;
  NSArray<NSString *> *patterns = @[@"(?m)^#{1,6}\\s+", @"(?m)^!\\[[^\\]]*\\]\\(", @"(?m)^[-*+]\\s+", @"(?m)^>\\s+", @"\\[[^\\]]+\\]\\([^)]+\\)", @"\\*\\*[^*]+\\*\\*"];
  for (NSString *pattern in patterns) {
    if ([self string:text matchesRegex:pattern]) return YES;
  }
  return NO;
}

- (NSArray<NSDictionary *> *)blocksFromMarkdown:(NSString *)markdown articleTitle:(NSString *)articleTitle {
  NSString *normalized = [self articleTextByRemovingReaderPreamble:markdown];
  NSArray<NSString *> *lines = [normalized componentsSeparatedByString:@"\n"];
  NSMutableArray<NSDictionary *> *blocks = [NSMutableArray array];
  NSMutableArray<NSString *> *paragraphLines = [NSMutableArray array];
  NSMutableArray<NSString *> *quoteLines = [NSMutableArray array];
  NSMutableArray<NSString *> *codeLines = [NSMutableArray array];
  BOOL inCode = NO;

  void (^flushParagraph)(void) = ^{
    if (paragraphLines.count == 0) return;
    NSString *text = [[paragraphLines componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length > 0) [blocks addObject:@{@"type": @"paragraph", @"text": text}];
    [paragraphLines removeAllObjects];
  };

  void (^flushQuote)(void) = ^{
    if (quoteLines.count == 0) return;
    NSString *text = [[quoteLines componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    text = [self stringByReplacingRegex:@"[\\t\\r\\n ]+" inString:text withString:@" "];
    if (text.length > 0) [blocks addObject:@{@"type": @"blockquote", @"text": text}];
    [quoteLines removeAllObjects];
  };

  for (NSString *line in lines) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed hasPrefix:@"```"]) {
      if (inCode) {
        [blocks addObject:@{@"type": @"code", @"text": [codeLines componentsJoinedByString:@"\n"] ?: @""}];
        [codeLines removeAllObjects];
        inCode = NO;
      } else {
        flushParagraph();
        flushQuote();
        inCode = YES;
      }
      continue;
    }
    if (inCode) {
      [codeLines addObject:line];
      continue;
    }

    NSDictionary *image = [self markdownImageBlockFromLine:trimmed];
    if (image) {
      flushParagraph();
      flushQuote();
      [blocks addObject:image];
      continue;
    }

    NSTextCheckingResult *quoteMatch = [self firstRegexMatch:@"^>\\s?(.*)$" inString:trimmed];
    if (quoteMatch && quoteMatch.numberOfRanges >= 2) {
      flushParagraph();
      NSString *text = [trimmed substringWithRange:[quoteMatch rangeAtIndex:1]];
      [quoteLines addObject:text];
      continue;
    }

    NSTextCheckingResult *headingMatch = [self firstRegexMatch:@"^(#{1,6})\\s+(.+)$" inString:trimmed];
    if (headingMatch && headingMatch.numberOfRanges >= 3) {
      flushParagraph();
      flushQuote();
      NSString *hashes = [trimmed substringWithRange:[headingMatch rangeAtIndex:1]];
      NSString *text = [trimmed substringWithRange:[headingMatch rangeAtIndex:2]];
      text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if (!(blocks.count == 0 && [text isEqualToString:articleTitle])) {
        [blocks addObject:@{@"type": @"heading", @"text": text, @"level": @(hashes.length)}];
      }
      continue;
    }

    NSTextCheckingResult *listMatch = [self firstRegexMatch:@"^([-*+]|\\d+\\.)\\s+(.+)$" inString:trimmed];
    if (listMatch && listMatch.numberOfRanges >= 3) {
      flushParagraph();
      flushQuote();
      NSString *marker = [trimmed substringWithRange:[listMatch rangeAtIndex:1]];
      NSString *text = [trimmed substringWithRange:[listMatch rangeAtIndex:2]];
      NSString *prefix = [marker hasSuffix:@"."] ? marker : @"•";
      [blocks addObject:@{@"type": @"list", @"text": [NSString stringWithFormat:@"%@ %@", prefix, text]}];
      continue;
    }

    if (trimmed.length == 0) {
      flushParagraph();
      flushQuote();
    } else {
      [paragraphLines addObject:trimmed];
    }
  }
  flushParagraph();
  flushQuote();
  if (codeLines.count > 0) [blocks addObject:@{@"type": @"code", @"text": [codeLines componentsJoinedByString:@"\n"] ?: @""}];
  return [blocks copy];
}

- (NSDictionary *)markdownImageBlockFromLine:(NSString *)line {
  NSTextCheckingResult *match = [self firstRegexMatch:@"!\\[([^\\]]*)\\]\\(([^\\s)]+)(?:\\s+\"[^\"]*\")?\\)" inString:line];
  if (!match || match.numberOfRanges < 3) return nil;
  NSString *alt = [line substringWithRange:[match rangeAtIndex:1]];
  NSString *url = [line substringWithRange:[match rangeAtIndex:2]];
  if (url.length == 0) return nil;
  return @{@"type": @"image", @"url": url, @"alt": alt ?: @""};
}

- (NSArray<NSDictionary *> *)blocksFromHTML:(NSString *)html articleTitle:(NSString *)articleTitle {
  return [self blocksFromHTML:html articleTitle:articleTitle baseURL:nil];
}

- (NSArray<NSDictionary *> *)blocksFromHTML:(NSString *)html articleTitle:(NSString *)articleTitle baseURL:(NSURL *)baseURL {
  NSString *fragment = [self articleBodyHTMLFragmentFromHTML:html];
  fragment = [self stringByReplacingRegex:@"<\\s*(script|style|svg|noscript)\\b[^>]*>.*?</\\s*\\1\\s*>" inString:fragment withString:@"" options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators)];

  NSMutableArray<NSDictionary *> *blocks = [NSMutableArray array];
  NSString *pattern = @"<\\s*(h[1-6]|p|li|blockquote|pre|code)\\b([^>]*)>(.*?)</\\s*\\1\\s*>|<\\s*img\\b([^>]*)>";
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators) error:nil];
  NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:fragment options:0 range:NSMakeRange(0, fragment.length)];

  for (NSTextCheckingResult *match in matches) {
    BOOL standaloneImage = match.numberOfRanges > 4 && [match rangeAtIndex:4].location != NSNotFound;
    if (standaloneImage) {
      NSString *attributes = [fragment substringWithRange:[match rangeAtIndex:4]];
      NSDictionary *imageBlock = [self imageBlockFromHTMLAttributes:attributes baseURL:baseURL];
      if (imageBlock) [blocks addObject:imageBlock];
      continue;
    }

    if (match.numberOfRanges < 4 || [match rangeAtIndex:1].location == NSNotFound || [match rangeAtIndex:3].location == NSNotFound) continue;
    NSString *tag = [[fragment substringWithRange:[match rangeAtIndex:1]] lowercaseString];
    NSString *innerHTML = [fragment substringWithRange:[match rangeAtIndex:3]];

    if ([tag hasPrefix:@"h"]) {
      NSString *text = [self markdownishTextFromHTMLFragment:innerHTML];
      if (text.length > 0 && !(blocks.count == 0 && [text isEqualToString:articleTitle])) {
        NSInteger level = [[tag substringFromIndex:1] integerValue];
        [blocks addObject:@{@"type": @"heading", @"text": text, @"level": @(MAX(1, level))}];
      }
    } else if ([tag isEqualToString:@"pre"] || [tag isEqualToString:@"code"]) {
      NSString *text = [self decodedHTMLText:[self strippedHTMLText:innerHTML]];
      if (text.length > 0) [blocks addObject:@{@"type": @"code", @"text": text}];
    } else if ([tag isEqualToString:@"blockquote"]) {
      NSString *text = [self markdownishTextFromHTMLFragment:innerHTML];
      if (text.length > 0) [blocks addObject:@{@"type": @"blockquote", @"text": text}];
    } else {
      [self appendBlocksFromHTMLInlineFragment:innerHTML toArray:blocks listItem:[tag isEqualToString:@"li"] baseURL:baseURL];
    }
  }

  if (blocks.count > 0) return [blocks copy];

  NSString *normalized = [self stringByReplacingRegex:@"<\\s*br\\s*/?\\s*>" inString:fragment withString:@"\n"];
  normalized = [self stringByReplacingRegex:@"</\\s*(p|div|li|blockquote|h[1-6])\\s*>" inString:normalized withString:@"\n\n"];
  NSString *plain = [self decodedHTMLText:[self strippedHTMLText:normalized]];
  return [self blocksFromMarkdown:plain articleTitle:articleTitle];
}

- (NSString *)articleBodyHTMLFragmentFromHTML:(NSString *)html {
  NSString *normalized = [[html ?: @"" stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
  if (normalized.length == 0) return @"";

  NSArray<NSString *> *patterns = @[
    @"<article\\b(?=[^>]*\\bclass=[\"'][^\"']*\\bcontent\\b)[^>]*>(.*?)</article>",
    @"<article\\b[^>]*>(.*?)</article>",
    @"<main\\b[^>]*>(.*?)</main>",
    @"<body\\b[^>]*>(.*?)</body>"
  ];

  for (NSString *pattern in patterns) {
    NSString *fragment = [self firstCapturedGroupForPattern:pattern inString:normalized options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators)];
    if (fragment.length > 0) return fragment;
  }
  return normalized;
}

- (void)appendBlocksFromHTMLInlineFragment:(NSString *)fragment toArray:(NSMutableArray<NSDictionary *> *)blocks listItem:(BOOL)listItem baseURL:(NSURL *)baseURL {
  NSString *html = fragment ?: @"";
  NSRegularExpression *imageRegex = [NSRegularExpression regularExpressionWithPattern:@"<\\s*img\\b([^>]*)>" options:NSRegularExpressionCaseInsensitive error:nil];
  NSArray<NSTextCheckingResult *> *matches = [imageRegex matchesInString:html options:0 range:NSMakeRange(0, html.length)];
  NSUInteger cursor = 0;

  void (^appendText)(NSString *) = ^(NSString *value) {
    NSString *text = [self markdownishTextFromHTMLFragment:value];
    if (text.length == 0) return;
    [blocks addObject:@{@"type": listItem ? @"list" : @"paragraph", @"text": listItem ? [NSString stringWithFormat:@"• %@", text] : text}];
  };

  for (NSTextCheckingResult *match in matches) {
    if (match.range.location > cursor) {
      NSRange beforeRange = NSMakeRange(cursor, match.range.location - cursor);
      appendText([html substringWithRange:beforeRange]);
    }
    if (match.numberOfRanges > 1 && [match rangeAtIndex:1].location != NSNotFound) {
      NSString *attributes = [html substringWithRange:[match rangeAtIndex:1]];
      NSDictionary *imageBlock = [self imageBlockFromHTMLAttributes:attributes baseURL:baseURL];
      if (imageBlock) [blocks addObject:imageBlock];
    }
    cursor = NSMaxRange(match.range);
  }

  if (cursor < html.length) {
    appendText([html substringFromIndex:cursor]);
  }
}

- (NSDictionary *)imageBlockFromHTMLAttributes:(NSString *)attributes baseURL:(NSURL *)baseURL {
  NSString *src = [self htmlAttribute:@"src" fromAttributes:attributes];
  src = [self absoluteURLStringFromURLString:src baseURL:baseURL];
  if (src.length == 0) return nil;
  NSString *alt = [self htmlAttribute:@"alt" fromAttributes:attributes];
  return @{@"type": @"image", @"url": src, @"alt": alt ?: @""};
}

- (NSString *)htmlAttribute:(NSString *)name fromAttributes:(NSString *)attributes {
  if (name.length == 0 || attributes.length == 0) return @"";
  NSString *pattern = [NSString stringWithFormat:@"(?:^|\\s)%@\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))", name];
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
  NSTextCheckingResult *match = [regex firstMatchInString:attributes options:0 range:NSMakeRange(0, attributes.length)];
  if (!match) return @"";
  for (NSUInteger index = 1; index < match.numberOfRanges; index++) {
    NSRange range = [match rangeAtIndex:index];
    if (range.location != NSNotFound && range.length > 0) {
      return [self decodedHTMLText:[attributes substringWithRange:range]];
    }
  }
  return @"";
}

- (NSString *)absoluteURLStringFromURLString:(NSString *)urlString baseURL:(NSURL *)baseURL {
  NSString *trimmed = [urlString stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (trimmed.length == 0) return @"";
  if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"]) return trimmed;
  if ([trimmed hasPrefix:@"//"]) {
    NSString *scheme = baseURL.scheme.length > 0 ? baseURL.scheme : @"https";
    return [NSString stringWithFormat:@"%@:%@", scheme, trimmed];
  }
  NSURL *resolved = [NSURL URLWithString:trimmed relativeToURL:baseURL];
  return resolved.absoluteURL.absoluteString ?: @"";
}

- (NSArray<NSDictionary *> *)blocksFromLeafletContent:(id)content {
  if (![content isKindOfClass:NSDictionary.class]) return @[];
  NSMutableArray<NSDictionary *> *blocks = [NSMutableArray array];
  [self appendBlocksFromObject:content toArray:blocks];
  return [blocks copy];
}

- (void)appendBlocksFromObject:(id)object toArray:(NSMutableArray<NSDictionary *> *)blocks {
  if ([object isKindOfClass:NSArray.class]) {
    for (id item in (NSArray *)object) [self appendBlocksFromObject:item toArray:blocks];
    return;
  }
  if (![object isKindOfClass:NSDictionary.class]) return;
  NSDictionary *dictionary = (NSDictionary *)object;
  NSString *type = [self stringFromValue:dictionary[@"$type"]].lowercaseString;
  NSString *text = [self blockTextFromDictionary:dictionary];
  if ([type rangeOfString:@"header"].location != NSNotFound || [type rangeOfString:@"heading"].location != NSNotFound) {
    if (text.length > 0) [blocks addObject:@{@"type": @"heading", @"text": text, @"level": @2}];
  } else if ([type rangeOfString:@"image"].location != NSNotFound) {
    NSString *url = [self imageURLFromObject:dictionary article:nil];
    NSMutableDictionary *imageBlock = [@{@"type": @"image", @"raw": dictionary, @"alt": [self stringFromValue:dictionary[@"alt"]]} mutableCopy];
    if (url.length > 0) imageBlock[@"url"] = url;
    [blocks addObject:imageBlock];
  } else if ([type rangeOfString:@"code"].location != NSNotFound) {
    if (text.length > 0) [blocks addObject:@{@"type": @"code", @"text": text}];
  } else if ([type rangeOfString:@"list"].location != NSNotFound) {
    NSArray *items = [dictionary[@"items"] isKindOfClass:NSArray.class] ? dictionary[@"items"] : @[];
    for (id item in items) {
      NSString *itemText = [self blockTextFromDictionary:[item isKindOfClass:NSDictionary.class] ? item : @{@"text": item ?: @""}];
      if (itemText.length > 0) [blocks addObject:@{@"type": @"list", @"text": [NSString stringWithFormat:@"• %@", itemText]}];
    }
  } else if ([type rangeOfString:@"text"].location != NSNotFound && text.length > 0) {
    [blocks addObject:@{@"type": @"paragraph", @"text": text}];
  }

  for (NSString *key in @[@"pages", @"blocks", @"children"]) {
    id child = dictionary[key];
    if (child) [self appendBlocksFromObject:child toArray:blocks];
  }
}

- (NSString *)blockTextFromDictionary:(NSDictionary *)dictionary {
  for (NSString *key in @[@"text", @"plainText", @"markdown", @"value", @"content"]) {
    id value = dictionary[key];
    if ([value isKindOfClass:NSString.class]) return [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  }
  return @"";
}

- (void)renderArticleBlocks:(NSArray<NSDictionary *> *)blocks article:(NSDictionary *)article {
  for (NSDictionary *block in blocks) {
    NSString *type = [self stringFromValue:block[@"type"]];
    if ([type isEqualToString:@"image"]) {
      NSString *url = [self imageURLFromObject:block article:article];
      if (url.length > 0) [self.articleContentStack addArrangedSubview:[self articleImageViewForURL:url alt:[self stringFromValue:block[@"alt"]]]];
      continue;
    }

    NSString *text = [self stringFromValue:block[@"text"]];
    if (text.length == 0) continue;
    UILabel *label = nil;
    if ([type isEqualToString:@"heading"]) {
      NSInteger level = [block[@"level"] respondsToSelector:@selector(integerValue)] ? [block[@"level"] integerValue] : 2;
      CGFloat size = level <= 1 ? 21.0 : (level == 2 ? 19.0 : 17.0);
      label = [self articleTextLabelWithFont:NFBFont(size, NFBFontWeightBold) textColor:NFBColorText()];
      label.attributedText = [self attributedTextForMarkdownInlineText:text font:label.font textColor:NFBColorText()];
    } else if ([type isEqualToString:@"code"]) {
      label = [self articleTextLabelWithFont:[UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightRegular] textColor:NFBColorText()];
      label.text = text;
      label.backgroundColor = NFBColorElevatedBackground();
      label.layer.cornerRadius = 8.0;
      label.layer.masksToBounds = YES;
    } else if ([type isEqualToString:@"blockquote"]) {
      [self.articleContentStack addArrangedSubview:[self articleBlockquoteViewWithText:text]];
      continue;
    } else {
      label = [self articleTextLabelWithFont:NFBFont(17.0, NFBFontWeightRegular) textColor:NFBColorText()];
      label.attributedText = [self attributedTextForMarkdownInlineText:text font:label.font textColor:NFBColorText()];
    }
    [self.articleContentStack addArrangedSubview:label];
  }
}

- (UIView *)articleBlockquoteViewWithText:(NSString *)text {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;

  UIView *rail = [[UIView alloc] init];
  rail.translatesAutoresizingMaskIntoConstraints = NO;
  rail.backgroundColor = NFBColorAccent();
  rail.layer.cornerRadius = 1.5;

  UILabel *label = [self articleTextLabelWithFont:NFBFont(17.0, NFBFontWeightRegular) textColor:NFBColorSecondaryText()];
  label.font = [UIFont italicSystemFontOfSize:17.0];
  label.attributedText = [self attributedTextForMarkdownInlineText:text font:label.font textColor:NFBColorSecondaryText()];
  label.translatesAutoresizingMaskIntoConstraints = NO;

  [container addSubview:rail];
  [container addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [rail.topAnchor constraintEqualToAnchor:container.topAnchor],
    [rail.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [rail.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    [rail.widthAnchor constraintEqualToConstant:3.0],
    [label.topAnchor constraintEqualToAnchor:container.topAnchor],
    [label.leadingAnchor constraintEqualToAnchor:rail.trailingAnchor constant:11.0],
    [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor]
  ]];
  return container;
}

- (UILabel *)articleTextLabelWithFont:(UIFont *)font textColor:(UIColor *)textColor {
  UILabel *label = [[UILabel alloc] init];
  label.font = font;
  label.textColor = textColor;
  label.numberOfLines = 0;
  label.lineBreakMode = NSLineBreakByWordWrapping;
  return label;
}

- (UIView *)articleImageViewForURL:(NSString *)url alt:(NSString *)alt {
  UIView *container = [[UIView alloc] init];
  container.translatesAutoresizingMaskIntoConstraints = NO;
  container.clipsToBounds = YES;
  container.layer.cornerRadius = 10.0;
  container.backgroundColor = NFBColorElevatedBackground();
  container.tag = 1901;

  UIImageView *imageView = [[UIImageView alloc] init];
  imageView.translatesAutoresizingMaskIntoConstraints = NO;
  imageView.contentMode = UIViewContentModeScaleAspectFit;
  imageView.clipsToBounds = NO;
  imageView.accessibilityLabel = alt;
  [container addSubview:imageView];

  NSLayoutConstraint *height = [container.heightAnchor constraintEqualToConstant:[self articleImageHeightForWidth:CGRectGetWidth(self.bounds) - 24.0]];
  [self.articleImageHeightConstraints addObject:height];
  [NSLayoutConstraint activateConstraints:@[
    [imageView.topAnchor constraintEqualToAnchor:container.topAnchor],
    [imageView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
    [imageView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
    [imageView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
    height
  ]];
  [self loadArticleImageURL:url intoImageView:imageView];
  return container;
}

- (NSString *)imageURLFromObject:(id)object article:(NSDictionary *)article {
  if ([object isKindOfClass:NSString.class]) {
    NSString *value = [(NSString *)object stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [value hasPrefix:@"http://"] || [value hasPrefix:@"https://"] ? value : @"";
  }
  if (![object isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *dictionary = (NSDictionary *)object;
  for (NSString *key in @[@"url", @"src", @"href", @"uri", @"fullsize", @"thumb"]) {
    NSString *value = [self imageURLFromObject:dictionary[key] article:article];
    if (value.length > 0) return value;
  }
  for (NSString *key in @[@"image", @"blob", @"file", @"media", @"raw"]) {
    NSString *value = [self imageURLFromObject:dictionary[key] article:article];
    if (value.length > 0) return value;
  }

  NSString *cid = [self blobCIDFromObject:dictionary];
  NSString *did = [self didFromArticle:article];
  if (cid.length > 0 && did.length > 0) {
    return [NSString stringWithFormat:@"https://cdn.bsky.app/img/feed_fullsize/plain/%@/%@@jpeg", did, cid];
  }
  return @"";
}

- (NSString *)blobCIDFromObject:(id)object {
  if ([object isKindOfClass:NSString.class]) return (NSString *)object;
  if (![object isKindOfClass:NSDictionary.class]) return @"";
  NSDictionary *dictionary = (NSDictionary *)object;
  NSString *link = [self stringFromValue:dictionary[@"$link"]];
  if (link.length > 0) return link;
  NSString *cid = [self stringFromValue:dictionary[@"cid"]];
  if (cid.length > 0) return cid;
  id ref = dictionary[@"ref"];
  if (ref) return [self blobCIDFromObject:ref];
  return @"";
}

- (NSString *)didFromArticle:(NSDictionary *)article {
  NSString *uri = [self stringFromValue:article[@"documentURI"]];
  if (![uri hasPrefix:@"at://"]) return @"";
  NSString *rest = [uri substringFromIndex:5];
  NSArray<NSString *> *parts = [rest componentsSeparatedByString:@"/"];
  return parts.count > 0 ? parts.firstObject : @"";
}

- (NSAttributedString *)attributedTextForMarkdownInlineText:(NSString *)text font:(UIFont *)font textColor:(UIColor *)textColor {
  NSString *safeText = text ?: @"";
  UIFont *resolvedFont = font ?: NFBFont(17.0, NFBFontWeightRegular);
  NSMutableAttributedString *attributed = [[NSMutableAttributedString alloc] initWithString:safeText attributes:@{
    NSFontAttributeName: resolvedFont,
    NSForegroundColorAttributeName: textColor ?: NFBColorText()
  }];
  [self applyMarkdownLinksToAttributedString:attributed];
  [self applyMarkdownMarker:@"\\*\\*([^*]+)\\*\\*" toAttributedString:attributed baseFont:resolvedFont];
  [self applyMarkdownMarker:@"__([^_]+)__" toAttributedString:attributed baseFont:resolvedFont];
  [self removeMarkdownMarker:@"`([^`]+)`" fromAttributedString:attributed font:[UIFont monospacedSystemFontOfSize:resolvedFont.pointSize - 1.0 weight:UIFontWeightRegular]];
  [self removeMarkdownMarker:@"\\*([^*]+)\\*" fromAttributedString:attributed font:[UIFont italicSystemFontOfSize:resolvedFont.pointSize]];
  [self removeMarkdownMarker:@"_([^_]+)_" fromAttributedString:attributed font:[UIFont italicSystemFontOfSize:resolvedFont.pointSize]];
  return attributed;
}

- (void)applyMarkdownLinksToAttributedString:(NSMutableAttributedString *)attributed {
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"!?\\[([^\\]]+)\\]\\(([^)]*)\\)" options:0 error:&error];
  if (error || !regex) return;
  while (YES) {
    NSString *string = attributed.string;
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || match.numberOfRanges < 3) break;
    NSString *token = [string substringWithRange:match.range];
    NSString *replacement = [string substringWithRange:[match rangeAtIndex:1]];
    BOOL image = [token hasPrefix:@"!"];
    [attributed replaceCharactersInRange:match.range withString:replacement];
    if (!image) {
      [attributed addAttribute:NSForegroundColorAttributeName value:NFBColorAccent() range:NSMakeRange(match.range.location, replacement.length)];
    }
  }
}

- (void)applyMarkdownMarker:(NSString *)pattern toAttributedString:(NSMutableAttributedString *)attributed baseFont:(UIFont *)baseFont {
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error || !regex) return;
  while (YES) {
    NSString *string = attributed.string;
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || match.numberOfRanges < 2) break;
    NSRange inner = [match rangeAtIndex:1];
    NSString *replacement = [string substringWithRange:inner];
    [attributed replaceCharactersInRange:match.range withString:replacement];
    [attributed addAttribute:NSFontAttributeName value:NFBFont(baseFont.pointSize, NFBFontWeightBold) range:NSMakeRange(match.range.location, replacement.length)];
  }
}

- (void)removeMarkdownMarker:(NSString *)pattern fromAttributedString:(NSMutableAttributedString *)attributed font:(UIFont *)font {
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error || !regex) return;
  while (YES) {
    NSString *string = attributed.string;
    NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
    if (!match || match.numberOfRanges < 2) break;
    NSString *replacement = [string substringWithRange:[match rangeAtIndex:1]];
    [attributed replaceCharactersInRange:match.range withString:replacement];
    [attributed addAttribute:NSFontAttributeName value:font range:NSMakeRange(match.range.location, replacement.length)];
  }
}

- (NSString *)strippedMarkdownText:(NSString *)text {
  NSString *clean = text ?: @"";
  clean = [self stringByReplacingRegex:@"!?\\[([^\\]]+)\\]\\([^)]*\\)" inString:clean withString:@"$1"];
  clean = [self stringByReplacingRegex:@"\\*\\*([^*]+)\\*\\*" inString:clean withString:@"$1"];
  clean = [self stringByReplacingRegex:@"__([^_]+)__" inString:clean withString:@"$1"];
  clean = [self stringByReplacingRegex:@"`([^`]+)`" inString:clean withString:@"$1"];
  return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)markdownishTextFromHTMLFragment:(NSString *)fragment {
  NSString *clean = fragment ?: @"";
  clean = [self stringByReplacingRegex:@"<\\s*a\\b[^>]*href=[\"']?([^\"' >]+)[\"']?[^>]*>(.*?)</\\s*a\\s*>" inString:clean withString:@"[$2]($1)" options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators)];
  clean = [self stringByReplacingRegex:@"<\\s*(strong|b)\\b[^>]*>(.*?)</\\s*\\1\\s*>" inString:clean withString:@"**$2**" options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators)];
  clean = [self stringByReplacingRegex:@"<\\s*(em|i)\\b[^>]*>(.*?)</\\s*\\1\\s*>" inString:clean withString:@"_$2_" options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators)];
  clean = [self stringByReplacingRegex:@"<\\s*code\\b[^>]*>(.*?)</\\s*code\\s*>" inString:clean withString:@"`$1`" options:(NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators)];
  clean = [self stringByReplacingRegex:@"<\\s*br\\s*/?\\s*>" inString:clean withString:@"\n"];
  clean = [self strippedHTMLText:clean];
  clean = [self decodedHTMLText:clean];
  clean = [self stringByReplacingRegex:@"[\\t\\r\\n ]+" inString:clean withString:@" "];
  return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)strippedHTMLText:(NSString *)text {
  NSString *clean = [self stringByReplacingRegex:@"<[^>]+>" inString:text ?: @"" withString:@""];
  return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)decodedHTMLText:(NSString *)text {
  if (text.length == 0) return @"";
  NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (data.length == 0) return text;
  NSDictionary *options = @{
    NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
    NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
  };
  NSAttributedString *decoded = [[NSAttributedString alloc] initWithData:data options:options documentAttributes:nil error:nil];
  NSString *string = decoded.string.length > 0 ? decoded.string : text;
  return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)firstCapturedGroupForPattern:(NSString *)pattern inString:(NSString *)string options:(NSRegularExpressionOptions)options {
  if (pattern.length == 0 || string.length == 0) return @"";
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:nil];
  NSTextCheckingResult *match = [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
  if (!match || match.numberOfRanges < 2) return @"";
  NSRange range = [match rangeAtIndex:1];
  if (range.location == NSNotFound || range.length == 0) return @"";
  return [string substringWithRange:range];
}

- (NSTextCheckingResult *)firstRegexMatch:(NSString *)pattern inString:(NSString *)string {
  if (pattern.length == 0 || string.length == 0) return nil;
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:&error];
  if (error || !regex) return nil;
  return [regex firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
}

- (NSString *)stringByReplacingRegex:(NSString *)pattern inString:(NSString *)string withString:(NSString *)replacement {
  return [self stringByReplacingRegex:pattern inString:string withString:replacement options:NSRegularExpressionCaseInsensitive];
}

- (NSString *)stringByReplacingRegex:(NSString *)pattern inString:(NSString *)string withString:(NSString *)replacement options:(NSRegularExpressionOptions)options {
  if (pattern.length == 0 || string.length == 0) return string ?: @"";
  NSError *error = nil;
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:&error];
  if (error || !regex) return string;
  return [regex stringByReplacingMatchesInString:string options:0 range:NSMakeRange(0, string.length) withTemplate:replacement ?: @""];
}

- (BOOL)string:(NSString *)string matchesRegex:(NSString *)pattern {
  return [self firstRegexMatch:pattern inString:string] != nil;
}

- (NSString *)stringFromValue:(id)value {
  return [value isKindOfClass:NSString.class] ? (NSString *)value : @"";
}

- (NSString *)metaTextWithDomain:(NSString *)domain sourceTitle:(NSString *)sourceTitle url:(NSString *)url {
  NSString *primary = domain.length > 0 ? domain : (sourceTitle.length > 0 ? sourceTitle : url);
  return primary ?: @"";
}

+ (UIColor *)sourceAccentColorForCard:(NSDictionary *)card {
  NSDictionary *source = [card[@"source"] isKindOfClass:NSDictionary.class] ? card[@"source"] : nil;
  NSDictionary *theme = [source[@"theme"] isKindOfClass:NSDictionary.class] ? source[@"theme"] : nil;
  NSDictionary *accentRGB = [theme[@"accentRGB"] isKindOfClass:NSDictionary.class] ? theme[@"accentRGB"] : nil;
  NSNumber *r = [accentRGB[@"r"] respondsToSelector:@selector(floatValue)] ? accentRGB[@"r"] : nil;
  NSNumber *g = [accentRGB[@"g"] respondsToSelector:@selector(floatValue)] ? accentRGB[@"g"] : nil;
  NSNumber *b = [accentRGB[@"b"] respondsToSelector:@selector(floatValue)] ? accentRGB[@"b"] : nil;
  if (r && g && b) {
    return [UIColor colorWithRed:MAX(0.0, MIN(255.0, r.floatValue)) / 255.0
                           green:MAX(0.0, MIN(255.0, g.floatValue)) / 255.0
                            blue:MAX(0.0, MIN(255.0, b.floatValue)) / 255.0
                           alpha:1.0];
  }
  return nil;
}

- (void)setQuotedCardStyle:(BOOL)quotedCardStyle {
  _quotedCardStyle = quotedCardStyle;
  [self applyTheme];
}

- (void)applyTheme {
  [self.richArticleReader applyTheme];
  if (self.quotedCardStyle) NFBIPAApplyEmbeddedAttachmentFrameAppearance(self);
  else NFBIPAApplyEmbeddedCardFrameAppearance(self);
  self.imageContainer.backgroundColor = NFBColorElevatedBackground();
  self.textContainer.backgroundColor = NFBColorBackground();
  self.metaLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  self.titleLabel.font = NFBFont(self.compact ? 14.0 : 15.0, NFBFontWeightRegular);
  self.descriptionLabel.font = NFBFont(15.0, NFBFontWeightRegular);
  self.readArticleLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.articleBodyLabel.font = NFBFont(17.0, NFBFontWeightRegular);
  self.metaLabel.textColor = NFBColorSecondaryText();
  self.sourceIconView.tintColor = NFBColorSecondaryText();
  self.titleLabel.textColor = NFBColorText();
  self.titleExternalIconView.tintColor = NFBColorSecondaryText();
  self.descriptionLabel.textColor = NFBColorSecondaryText();
  self.readArticleLabel.textColor = NFBColorAccent();
  self.readArticleIconView.tintColor = NFBColorAccent();
  self.articleSeparator.backgroundColor = NFBIPAEmbeddedCardBorderColor();
  self.articleBodyLabel.textColor = NFBColorText();
}

- (void)cardTapped {
  if ([self.delegate respondsToSelector:@selector(externalCardViewDidTapCard:)]) {
    [self.delegate externalCardViewDidTapCard:self];
  }
}

- (void)readArticleTapped:(UITapGestureRecognizer *)recognizer {
  (void)recognizer;
  if (self.readArticleContainer.hidden) return;
  if ([self.delegate respondsToSelector:@selector(externalCardViewDidTapReadOnWebsite:)]) {
    [self.delegate externalCardViewDidTapReadOnWebsite:self];
    return;
  }
  [self cardTapped];
}

- (void)loadImageURL:(NSString *)urlString intoImageView:(UIImageView *)imageView icon:(BOOL)icon {
  if (urlString.length == 0) {
    imageView.image = nil;
    return;
  }
  if (icon) self.sourceIconURLString = urlString;
  else self.imageURLString = urlString;

  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    imageView.image = cached;
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      NSString *current = icon ? self.sourceIconURLString : self.imageURLString;
      if ([current isEqualToString:urlString]) imageView.image = image;
    });
  }];
  [task resume];
}

- (void)loadArticleImageURL:(NSString *)urlString intoImageView:(UIImageView *)imageView {
  if (urlString.length == 0) {
    imageView.image = nil;
    return;
  }
  imageView.accessibilityIdentifier = urlString;

  UIImage *cached = [[self.class imageCache] objectForKey:urlString];
  if (cached) {
    imageView.image = cached;
    return;
  }

  NSURL *url = [NSURL URLWithString:urlString];
  if (!url) return;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    (void)response;
    if (error || data.length == 0) return;
    UIImage *image = [UIImage imageWithData:data];
    if (!image) return;
    [[self.class imageCache] setObject:image forKey:urlString];
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([imageView.accessibilityIdentifier isEqualToString:urlString]) imageView.image = image;
    });
  }];
  [task resume];
}

+ (NSCache *)imageCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 180;
  });
  return cache;
}

+ (NSCache *)articleHTMLBlockCache {
  static NSCache *cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[NSCache alloc] init];
    cache.countLimit = 80;
  });
  return cache;
}

@end
