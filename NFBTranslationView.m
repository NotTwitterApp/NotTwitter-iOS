#import "NFBTranslationView.h"
#import "NFBTheme.h"
#import <dlfcn.h>

// Stable Objective-C surface of the public Swift Translation API bridge.
@interface NFBTranslationBridge : NSObject
@property (class, nonatomic, readonly) BOOL available;
+ (void)candidateForText:(NSString *)text languages:(NSArray<NSString *> *)languages completion:(void (^)(NSString *, NSString *))completion;
+ (UIViewController *)controllerForText:(NSString *)text source:(NSString *)source target:(NSString *)target completion:(void (^)(NSString *, NSError *))completion;
@end

static Class NFBTranslationBridgeClass(void) {
  if ([NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){18, 0, 0}]) {
    static Class bridge;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"NFBTranslation.framework/NFBTranslation"];
      if (dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) bridge = NSClassFromString(@"NFBTranslationBridge");
    });
    return bridge;
  }
  return Nil;
}

@interface NFBTranslationButton : UIButton
@end
@implementation NFBTranslationButton
- (CGSize)intrinsicContentSize {
  CGSize size = [super intrinsicContentSize];
  if (self.bounds.size.width > 0) {
    size.height = ceil([self.titleLabel sizeThatFits:CGSizeMake(self.bounds.size.width, CGFLOAT_MAX)].height) + 6;
  }
  return size;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  if (fabs(self.titleLabel.preferredMaxLayoutWidth - self.bounds.size.width) > 0.5) {
    self.titleLabel.preferredMaxLayoutWidth = self.bounds.size.width;
    [self invalidateIntrinsicContentSize];
  }
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  return CGRectContainsPoint(CGRectInset(self.bounds, -4, -6), point);
}
@end

@interface NFBTranslationView ()
@property (nonatomic, strong) UIButton *translateButton;
@property (nonatomic, strong) UILabel *translatedLabel;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UIViewController *translationController;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray *identity;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSString *actionTitle;
@property (nonatomic) NSUInteger generation;
@property (nonatomic) BOOL showingTranslation;
@end

@implementation NFBTranslationView

+ (NSCache *)translations {
  static NSCache *cache;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 150; });
  return cache;
}

- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.axis = UILayoutConstraintAxisVertical;
    self.alignment = UIStackViewAlignmentFill;
    self.spacing = 6.0;
    self.hidden = YES;
    self.translateButton = [NFBTranslationButton buttonWithType:UIButtonTypeSystem];
    self.translateButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
    self.translateButton.titleLabel.numberOfLines = 0;
    self.translateButton.titleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.translateButton addTarget:self action:@selector(translateTapped) forControlEvents:UIControlEventTouchUpInside];
    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.hidden = YES;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[self.translateButton, self.spinner]];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 6;
    self.translatedLabel = [UILabel new];
    self.translatedLabel.numberOfLines = 0;
    self.translatedLabel.hidden = YES;
    self.errorLabel = [UILabel new];
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self addArrangedSubview:row];
    [self addArrangedSubview:self.translatedLabel];
    [self addArrangedSubview:self.errorLabel];
    [self applyTheme];
  }
  return self;
}

- (void)applyTheme {
  self.translateButton.titleLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  [self.translateButton setTitleColor:NFBColorAccent() forState:UIControlStateNormal];
  self.translatedLabel.textColor = NFBColorText();
  self.errorLabel.font = NFBFont(13.0, NFBFontWeightRegular);
  self.errorLabel.textColor = NFBColorSecondaryText();
  self.spinner.color = NFBColorSecondaryText();
}

- (void)removeTranslationController {
  [self.translationController willMoveToParentViewController:nil];
  [self.translationController.view removeFromSuperview];
  [self.translationController removeFromParentViewController];
  self.translationController = nil;
}

- (void)reset {
  self.generation++;
  [self removeTranslationController];
  self.identity = nil;
  self.text = nil;
  self.source = nil;
  self.target = nil;
  self.showingTranslation = NO;
  self.translatedLabel.text = nil;
  self.translatedLabel.hidden = YES;
  self.errorLabel.hidden = YES;
  [self.spinner stopAnimating];
  self.spinner.hidden = YES;
  self.translateButton.enabled = YES;
  self.translateButton.accessibilityHint = nil;
  self.hidden = YES;
}

- (void)configureWithPost:(NSDictionary *)post bodyFont:(UIFont *)font {
  NSDictionary *record = [post[@"record"] isKindOfClass:NSDictionary.class] ? post[@"record"] : @{};
  [self configureWithText:[record[@"text"] isKindOfClass:NSString.class] ? record[@"text"] : @""
               languages:[record[@"langs"] isKindOfClass:NSArray.class] ? record[@"langs"] : @[]
                   title:@"Translate Tweet" bodyFont:font];
}

- (void)configureWithText:(NSString *)text languages:(NSArray *)languages title:(NSString *)title bodyFont:(UIFont *)font {
  [self applyTheme];
  self.translatedLabel.font = font;
  NSArray *validLanguages = [languages filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id value, NSDictionary *bindings) {
    return [value isKindOfClass:NSString.class] && [value length] > 0;
  }]];
  NSArray *identity = @[text, validLanguages, NSLocale.preferredLanguages, title];
  if ([self.identity isEqual:identity]) return;
  [self reset];
  self.identity = identity;
  if (text.length == 0 || ![NFBTranslationBridgeClass() available]) return;
  self.text = text;
  self.actionTitle = title;
  [self.translateButton setTitle:title forState:UIControlStateNormal];
  NSUInteger generation = self.generation;
  __weak typeof(self) weakSelf = self;
  [NFBTranslationBridgeClass() candidateForText:text languages:validLanguages completion:^(NSString *source, NSString *target) {
    typeof(self) self = weakSelf;
    if (!self || self.generation != generation || !source.length || !target.length) return;
    self.source = source;
    self.target = target;
    self.hidden = NO;
    [self notifySizeChanged];
  }];
}

- (void)notifySizeChanged {
  [self invalidateIntrinsicContentSize];
  if (self.sizeChanged) { self.sizeChanged(); return; }
  UIView *view = self.superview;
  while (view && ![view isKindOfClass:UITableView.class]) view = view.superview;
  UITableView *table = (UITableView *)view;
  // Defer updates so reuse/configuration and SwiftUI completion can finish first.
  __weak UITableView *weakTable = table;
  dispatch_async(dispatch_get_main_queue(), ^{
    UITableView *table = weakTable;
    if (table.window) [UIView performWithoutAnimation:^{ [table beginUpdates]; [table endUpdates]; }];
  });
}

- (void)showTranslation:(NSString *)translation {
  self.showingTranslation = YES;
  self.translatedLabel.text = translation; // Original facet byte offsets do not apply to translated prose.
  self.translatedLabel.hidden = NO;
  NSString *language = [NSLocale.currentLocale localizedStringForLanguageCode:self.source] ?: self.source;
  [self.translateButton setTitle:[NSString stringWithFormat:@"Translated from %@ by Apple", language] forState:UIControlStateNormal];
  self.translateButton.accessibilityHint = @"Double-tap to hide translation";
  [self notifySizeChanged];
}

- (void)translateTapped {
  if (self.showingTranslation) {
    self.showingTranslation = NO;
    self.translatedLabel.hidden = YES;
    [self.translateButton setTitle:self.actionTitle forState:UIControlStateNormal];
    self.translateButton.accessibilityHint = nil;
    [self notifySizeChanged];
    return;
  }
  if (self.translationController || !self.source.length || !self.target.length) return;
  NSArray *key = @[self.text, self.source, self.target];
  NSString *cached = [self.class.translations objectForKey:key];
  if (cached) { [self showTranslation:cached]; return; }
  UIResponder *responder = self;
  while (responder && ![responder isKindOfClass:UIViewController.class]) responder = responder.nextResponder;
  UIViewController *parent = (UIViewController *)responder;
  if (!parent || !self.window) return;
  self.errorLabel.hidden = YES;
  self.translateButton.enabled = NO;
  [self.translateButton setTitle:@"Translating…" forState:UIControlStateNormal];
  self.spinner.hidden = NO;
  [self.spinner startAnimating];
  NSUInteger generation = self.generation;
  __weak typeof(self) weakSelf = self;
  UIViewController *host = [NFBTranslationBridgeClass() controllerForText:self.text source:self.source target:self.target completion:^(NSString *translation, NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) self = weakSelf;
      if (!self || self.generation != generation) return;
      [self removeTranslationController];
      [self.spinner stopAnimating];
      self.spinner.hidden = YES;
      self.translateButton.enabled = YES;
      if (translation.length > 0) {
        [self.class.translations setObject:translation forKey:key];
        [self showTranslation:translation];
      } else {
        [self.translateButton setTitle:self.actionTitle forState:UIControlStateNormal];
        self.errorLabel.text = @"Translation couldn’t be completed. Tap to try again.";
        self.errorLabel.hidden = NO;
        [self notifySizeChanged];
      }
    });
  }];
  self.translationController = host;
  [parent addChildViewController:host];
  // Keep the task in a real view hierarchy for Apple's download-consent UI.
  host.view.frame = CGRectMake(0, 0, MAX(1, self.bounds.size.width), 1);
  host.view.userInteractionEnabled = NO;
  host.view.accessibilityElementsHidden = YES;
  [self addSubview:host.view];
  [host didMoveToParentViewController:parent];
  [self notifySizeChanged];
}

- (void)didMoveToWindow {
  [super didMoveToWindow];
  if (!self.window && self.translationController) {
    self.generation++;
    [self removeTranslationController];
    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    self.translateButton.enabled = YES;
    [self.translateButton setTitle:self.actionTitle forState:UIControlStateNormal];
  }
}
@end
