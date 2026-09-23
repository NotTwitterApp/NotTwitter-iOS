#import "NFBEditProfileViewController.h"
#import "NFBProfileEditorService.h"
#import "NFBProfileRecord.h"
#import "NFBProfileEditorGeometry.h"
#import "NFBAtprotoSession.h"
#import "NFBTheme.h"
#import <PhotosUI/PhotosUI.h>
#import <ImageIO/ImageIO.h>

// The crop window is the exported image. Zoom and pan never expose empty pixels.
@interface NFBProfilePhotoCropController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic) BOOL banner;
@property (nonatomic, copy) void (^completion)(UIImage *);
@property (nonatomic, strong) UIScrollView *crop;
@property (nonatomic, strong) UIImageView *photo;
@property (nonatomic) CGSize previousSize;
@end
@implementation NFBProfilePhotoCropController
- (void)viewDidLoad {
  [super viewDidLoad]; self.title = @"Move and scale"; self.view.backgroundColor = UIColor.blackColor;
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(apply)];
  self.crop = [UIScrollView new]; self.crop.delegate = self; self.crop.clipsToBounds = YES; self.crop.bounces = NO; self.crop.bouncesZoom = NO;
  self.crop.showsHorizontalScrollIndicator = NO; self.crop.showsVerticalScrollIndicator = NO; self.crop.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
  self.photo = [[UIImageView alloc] initWithImage:self.image]; [self.crop addSubview:self.photo]; [self.view addSubview:self.crop];
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews]; CGRect safe = UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets);
  CGFloat w = MIN(safe.size.width, self.banner ? safe.size.height * 3 : safe.size.height), h = w / (self.banner ? 3 : 1);
  self.crop.frame = CGRectMake(CGRectGetMidX(safe)-w/2,CGRectGetMidY(safe)-h/2,w,h);
  if (CGSizeEqualToSize(self.previousSize,self.crop.bounds.size)) return;
  self.previousSize = self.crop.bounds.size; self.crop.zoomScale = 1;
  CGFloat scale = MAX(w/self.image.size.width,h/self.image.size.height);
  self.photo.frame = CGRectMake(0,0,self.image.size.width*scale,self.image.size.height*scale);
  self.crop.contentSize = self.photo.frame.size; self.crop.minimumZoomScale = 1; self.crop.maximumZoomScale = 5;
  self.crop.contentOffset = CGPointMake((self.photo.frame.size.width-w)/2,(self.photo.frame.size.height-h)/2);
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView { return self.photo; }
- (void)apply {
  CGSize size = self.banner ? CGSizeMake(1500,500) : CGSizeMake(600,600);
  CGFloat scale = size.width/self.crop.bounds.size.width;
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1; format.opaque = YES;
  UIImage *cropped = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [UIColor.whiteColor setFill]; UIRectFill((CGRect){CGPointZero,size});
    [self.image drawInRect:CGRectMake(-self.crop.contentOffset.x*scale,-self.crop.contentOffset.y*scale,self.photo.frame.size.width*scale,self.photo.frame.size.height*scale)];
  }];
  if (self.completion) self.completion(cropped);
  [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface NFBProfileBirthDateController : UIViewController
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) void (^completion)(NSString *);
@property (nonatomic, strong) UIDatePicker *picker;
@property (nonatomic, strong) UILabel *notice;
@property (nonatomic, strong) UIButton *remove;
@end
@implementation NFBProfileBirthDateController
- (NSDateFormatter *)formatter { NSDateFormatter *f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; f.dateFormat = @"yyyy-MM-dd"; return f; }
- (void)viewDidLoad {
  [super viewDidLoad]; self.title = @"Birth date"; self.view.backgroundColor = NFBColorBackground();
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Done" style:UIBarButtonItemStyleDone target:self action:@selector(done)];
  self.picker = [UIDatePicker new]; self.picker.datePickerMode = UIDatePickerModeDate; self.picker.preferredDatePickerStyle = UIDatePickerStyleWheels;
  self.picker.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian]; self.picker.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  self.picker.maximumDate = NSDate.date; self.picker.minimumDate = [[self formatter] dateFromString:@"1900-01-01"];
  self.picker.date = [[self formatter] dateFromString:self.value] ?: [[self formatter] dateFromString:@"2000-01-01"]; [self.view addSubview:self.picker];
  self.notice = [UILabel new]; self.notice.font = NFBFont(15,NFBFontWeightRegular); self.notice.textColor = NFBColorSecondaryText(); self.notice.numberOfLines = 0;
  self.notice.text = @"Your birth date is optional. If you add it, the full date will be public on your profile and ATProto. There are no private birthday visibility settings."; [self.view addSubview:self.notice];
  self.remove = [UIButton buttonWithType:UIButtonTypeSystem]; [self.remove setTitle:@"Remove birth date" forState:UIControlStateNormal]; self.remove.tintColor = UIColor.systemRedColor; [self.remove addTarget:self action:@selector(removeDate) forControlEvents:UIControlEventTouchUpInside]; [self.view addSubview:self.remove];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGRect r = UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets); self.picker.frame = CGRectMake(r.origin.x,r.origin.y,r.size.width,216); CGSize s = [self.notice sizeThatFits:CGSizeMake(r.size.width-32,CGFLOAT_MAX)]; self.notice.frame = CGRectMake(r.origin.x+16,CGRectGetMaxY(self.picker.frame)+20,r.size.width-32,s.height); self.remove.frame = CGRectMake(r.origin.x+16,CGRectGetMaxY(self.notice.frame)+16,r.size.width-32,44); }
- (void)done { if (self.completion) self.completion([[self formatter] stringFromDate:self.picker.date]); [self.navigationController popViewControllerAnimated:YES]; }
- (void)removeDate { if (self.completion) self.completion(@""); [self.navigationController popViewControllerAnimated:YES]; }
@end

@interface NFBEditProfileViewController () <UITextFieldDelegate,UITextViewDelegate,PHPickerViewControllerDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate,UIAdaptivePresentationControllerDelegate>
@property (nonatomic, strong) NSDictionary *profile;
@property (nonatomic, copy) void (^completion)(NSDictionary *);
@property (nonatomic, strong) NFBProfileEditorService *service;
@property (nonatomic, strong) NSDictionary *snapshot;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, strong) UIImageView *banner;
@property (nonatomic, strong) UIImageView *avatar;
@property (nonatomic, strong) UIButton *bannerButton;
@property (nonatomic, strong) UIButton *avatarButton;
@property (nonatomic, strong) NSMutableArray<UIView *> *rows;
@property (nonatomic, strong) NSMutableDictionary<NSString *,UITextField *> *fields;
@property (nonatomic, strong) UITextView *bio;
@property (nonatomic, strong) UILabel *bioPlaceholder;
@property (nonatomic, strong) UIButton *birthdayButton;
@property (nonatomic, copy) NSString *birthday;
@property (nonatomic, strong) UILabel *notice;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) NSMutableDictionary *imageEdits;
@property (nonatomic, strong) NSMutableDictionary *previewImages;
@property (nonatomic, strong) NSMutableDictionary *imageTasks;
@property (nonatomic, copy) NSString *pickingKey;
@property (nonatomic) BOOL busy;
@property (nonatomic) NSUInteger loadGeneration;
@end
@implementation NFBEditProfileViewController
- (instancetype)initWithProfile:(NSDictionary *)profile completion:(void (^)(NSDictionary *))completion {
  if ((self = [super init])) {
    _profile = [profile copy]; _completion = [completion copy];
    _service = [[NFBProfileEditorService alloc] initWithAccountDID:NFBProfileString(profile[@"did"])];
    _fields = [NSMutableDictionary new]; _rows = [NSMutableArray new]; _imageEdits = [NSMutableDictionary new]; _previewImages = [NSMutableDictionary new]; _imageTasks = [NSMutableDictionary new];
  }
  return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; for (NSURLSessionDataTask *task in self.imageTasks.allValues) [task cancel]; }
- (void)viewDidLoad {
  [super viewDidLoad]; self.title = @"Edit profile"; self.view.backgroundColor = NFBColorBackground(); self.overrideUserInterfaceStyle = NFBCurrentUserInterfaceStyle();
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
  self.scroll = [UIScrollView new]; self.scroll.delegate = self; self.scroll.alwaysBounceVertical = YES; self.scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  self.scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever; [self.view addSubview:self.scroll];
  self.banner = [UIImageView new]; self.banner.backgroundColor = NFBColorElevatedBackground(); self.banner.contentMode = UIViewContentModeScaleAspectFill; self.banner.clipsToBounds = YES; [self.scroll addSubview:self.banner];
  self.bannerButton = [self imageButton:@"Change header photo" action:@selector(editBanner)]; [self.scroll addSubview:self.bannerButton];
  self.avatar = [UIImageView new]; self.avatar.contentMode = UIViewContentModeScaleAspectFill; self.avatar.clipsToBounds = YES; self.avatar.layer.borderWidth = 4; self.avatar.layer.borderColor = NFBColorBackground().CGColor; [self.scroll addSubview:self.avatar];
  self.avatarButton = [self imageButton:@"Change profile photo" action:@selector(editAvatar)]; [self.scroll addSubview:self.avatarButton];
  [self addTextField:@"displayName" title:@"Name" placeholder:@"Add your name"];
  UIView *bioRow = [self rowWithTitle:@"Bio"]; self.bio = [UITextView new]; self.bio.delegate = self; self.bio.backgroundColor = UIColor.clearColor; self.bio.textColor = NFBColorText(); self.bio.font = NFBFont(17,NFBFontWeightRegular); self.bio.tintColor = NFBColorAccent(); self.bio.scrollEnabled = NO; self.bio.textContainerInset = UIEdgeInsetsZero; self.bio.textContainer.lineFragmentPadding = 0; self.bio.accessibilityLabel = @"Bio"; [bioRow addSubview:self.bio];
  self.bioPlaceholder = [UILabel new]; self.bioPlaceholder.text = @"Add your bio"; self.bioPlaceholder.font = self.bio.font; self.bioPlaceholder.textColor = NFBColorTertiaryText(); self.bioPlaceholder.userInteractionEnabled = NO; [bioRow addSubview:self.bioPlaceholder];
  [self addTextField:@"pronouns" title:@"Pronouns" placeholder:@"Optional, e.g. they/them"]; self.fields[@"pronouns"].autocapitalizationType = UITextAutocapitalizationTypeNone; self.fields[@"pronouns"].autocorrectionType = UITextAutocorrectionTypeNo;
  [self addTextField:@"com.nottwitter.location" title:@"Location" placeholder:@"Add your location"];
  [self addTextField:@"website" title:@"Website" placeholder:@"Add your website"]; self.fields[@"website"].keyboardType = UIKeyboardTypeURL; self.fields[@"website"].autocorrectionType = UITextAutocorrectionTypeNo; self.fields[@"website"].autocapitalizationType = UITextAutocapitalizationTypeNone;
  UIView *birthRow = [self rowWithTitle:@"Birth date"]; self.birthdayButton = [UIButton buttonWithType:UIButtonTypeSystem]; self.birthdayButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft; self.birthdayButton.titleLabel.font = NFBFont(17,NFBFontWeightRegular); self.birthdayButton.tintColor = NFBColorAccent(); self.birthdayButton.accessibilityLabel = @"Edit birth date"; [self.birthdayButton addTarget:self action:@selector(editBirthday) forControlEvents:UIControlEventTouchUpInside]; [birthRow addSubview:self.birthdayButton];
  self.notice = [UILabel new]; self.notice.numberOfLines = 0; self.notice.font = NFBFont(13,NFBFontWeightRegular); self.notice.textColor = NFBColorSecondaryText(); self.notice.text = @"Location and birth date are optional public profile fields. Other ATProto apps may not display them."; [self.scroll addSubview:self.notice];
  self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium]; self.spinner.hidesWhenStopped = YES; [self.view addSubview:self.spinner];
  [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
  [self loadProfile];
}
- (UIButton *)imageButton:(NSString *)label action:(SEL)action {
  UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom]; button.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.3]; button.tintColor = UIColor.whiteColor; button.accessibilityLabel = label;
  [button setImage:NFBTemplateIcon(@"nfb_camera") forState:UIControlStateNormal]; button.imageView.contentMode = UIViewContentModeScaleAspectFit; button.imageView.alpha = 0.85; [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}
- (UIView *)rowWithTitle:(NSString *)title {
  UIView *row = [UIView new]; UILabel *label = [UILabel new]; label.tag = 1; label.text = title; label.font = NFBFont(17,NFBFontWeightBold); label.textColor = NFBColorText(); [row addSubview:label];
  UIView *line = [UIView new]; line.tag = 2; NFBIPAApplyTableSeparatorAppearance(line); [row addSubview:line]; [self.scroll addSubview:row]; [self.rows addObject:row]; return row;
}
- (void)addTextField:(NSString *)key title:(NSString *)title placeholder:(NSString *)placeholder {
  UIView *row = [self rowWithTitle:title]; UITextField *field = [UITextField new]; field.font = NFBFont(17,NFBFontWeightRegular); field.textColor = NFBColorText(); field.tintColor = NFBColorAccent(); field.delegate = self; field.accessibilityLabel = title;
  field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder attributes:@{NSForegroundColorAttributeName:NFBColorTertiaryText()}]; field.returnKeyType = UIReturnKeyDone; [field addTarget:self action:@selector(changed) forControlEvents:UIControlEventEditingChanged]; [row addSubview:field]; self.fields[key] = field;
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; self.navigationController.presentationController.delegate = self; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews]; self.scroll.frame = UIEdgeInsetsInsetRect(self.view.bounds,self.view.safeAreaInsets); CGFloat width = self.scroll.bounds.size.width;
  BOOL landscape = self.view.bounds.size.width > self.view.bounds.size.height;
  CGFloat bannerHeight = NFBProfileEditorBannerHeight(width,landscape), avatarSize = MIN(120,ceil(NFBFont(17,NFBFontWeightRegular).lineHeight*3.66));
  [self layoutPhotoHeaderWithWidth:width bannerHeight:bannerHeight avatarSize:avatarSize];
  CGFloat y = bannerHeight+60, titleWidth = 0, pad = 16;
  for (UIView *row in self.rows) titleWidth = MAX(titleWidth,[(UILabel *)[row viewWithTag:1] sizeThatFits:CGSizeMake(width,100)].width);
  CGFloat x = pad+ceil(titleWidth)+16, fieldWidth = MAX(80,width-x-pad);
  CGFloat baseHeight = MAX(45,ceil(NFBFont(17,NFBFontWeightRegular).lineHeight)+24);
  NSArray *inputs = @[self.fields[@"displayName"],self.bio,self.fields[@"pronouns"],self.fields[@"com.nottwitter.location"],self.fields[@"website"],self.birthdayButton];
  for (NSUInteger i=0;i<self.rows.count;i++) {
    UIView *row = self.rows[i], *input = inputs[i]; CGFloat height = baseHeight;
    if (input == self.bio) height = MAX(baseHeight,[self.bio sizeThatFits:CGSizeMake(fieldWidth,CGFLOAT_MAX)].height+24);
    row.frame = CGRectMake(0,y,width,height); [row viewWithTag:1].frame = CGRectMake(pad,12,titleWidth,NFBFont(17,NFBFontWeightRegular).lineHeight);
    [row viewWithTag:2].frame = CGRectMake(0,height-NFBIPATableSeparatorHeight(),width,NFBIPATableSeparatorHeight());
    input.frame = CGRectMake(x,12,fieldWidth,height-24);
    if (input == self.bio) self.bioPlaceholder.frame = CGRectMake(x,12,fieldWidth,self.bio.font.lineHeight);
    y += height;
  }
  CGSize note = [self.notice sizeThatFits:CGSizeMake(width-32,CGFLOAT_MAX)]; self.notice.frame = CGRectMake(16,y+16,width-32,note.height); y = CGRectGetMaxY(self.notice.frame)+32;
  self.scroll.contentSize = CGSizeMake(width,y); self.spinner.center = CGPointMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds));
}
- (void)layoutPhotoHeaderWithWidth:(CGFloat)width bannerHeight:(CGFloat)bannerHeight avatarSize:(CGFloat)avatarSize {
  CGFloat offset = self.scroll.contentOffset.y, pull = MIN(0,offset), height = bannerHeight-pull;
  self.banner.frame = CGRectMake(0,pull,width,height); self.bannerButton.frame = self.banner.frame;
  self.bannerButton.imageEdgeInsets = UIEdgeInsetsMake((height-32)/2,(width-32)/2,(height-32)/2,(width-32)/2);
  self.bannerButton.imageView.alpha = MAX(0,MIN(0.85,0.85+MIN(0,offset)/MAX(1,bannerHeight)));
  CGFloat scale = NFBProfileEditorAvatarScale(offset,bannerHeight), border = ceil(avatarSize*0.05);
  CGPoint center = CGPointMake(16+avatarSize/2,NFBProfileEditorAvatarCenterY(bannerHeight,avatarSize,scale));
  self.avatar.transform = CGAffineTransformIdentity; self.avatar.bounds = CGRectMake(0,0,avatarSize,avatarSize); self.avatar.center = center;
  self.avatar.layer.cornerRadius = avatarSize/2; self.avatar.layer.borderWidth = border;
  self.avatarButton.transform = CGAffineTransformIdentity; self.avatarButton.bounds = CGRectMake(0,0,avatarSize-2*border,avatarSize-2*border); self.avatarButton.center = center;
  self.avatarButton.layer.cornerRadius = self.avatarButton.bounds.size.width/2;
  CGFloat inset = (self.avatarButton.bounds.size.width-32)/2; self.avatarButton.imageEdgeInsets = UIEdgeInsetsMake(inset,inset,inset,inset);
  self.avatar.transform = CGAffineTransformMakeScale(scale,scale); self.avatarButton.transform = self.avatar.transform;
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
  if (scrollView != self.scroll) return;
  CGFloat width = scrollView.bounds.size.width;
  [self layoutPhotoHeaderWithWidth:width bannerHeight:NFBProfileEditorBannerHeight(width,self.view.bounds.size.width>self.view.bounds.size.height) avatarSize:MIN(120,ceil(NFBFont(17,NFBFontWeightRegular).lineHeight*3.66))];
}
- (void)setWorking:(BOOL)working {
  self.busy = working; self.scroll.userInteractionEnabled = !working && self.snapshot != nil; self.navigationItem.leftBarButtonItem.enabled = !working || !self.snapshot;
  if (working) [self.spinner startAnimating]; else [self.spinner stopAnimating]; [self changed];
}
- (void)loadProfile {
  NSUInteger generation = ++self.loadGeneration; [self setWorking:YES];
  __weak typeof(self) weakSelf = self;
  [self.service loadWithCompletion:^(NSDictionary *snapshot, NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{
    typeof(self) self = weakSelf; if (!self || generation != self.loadGeneration) return;
    if (error) { [self setWorking:NO]; [self showError:error reload:YES]; return; }
    self.snapshot = snapshot; [self.imageEdits removeAllObjects]; [self.previewImages removeAllObjects];
    NSDictionary *record = snapshot[@"value"];
    for (NSString *key in self.fields) self.fields[key].text = NFBProfileString(record[key]);
    self.bio.text = NFBProfileString(record[@"description"]); self.birthday = NFBProfileString(record[@"com.nottwitter.birthDate"]); [self updateBirthday];
    self.profile = NFBProfileViewApplyingRecord(self.profile,record,snapshot[@"endpoint"]);
    [self loadImage:@"avatar"]; [self loadImage:@"banner"]; [self setWorking:NO]; [self.view setNeedsLayout];
  }); }];
}
- (void)loadImage:(NSString *)key {
  [self.imageTasks[key] cancel]; [self.imageTasks removeObjectForKey:key];
  UIImageView *target = [key isEqual:@"avatar"] ? self.avatar : self.banner;
  target.image = [key isEqual:@"avatar"] ? NFBDefaultAvatarImage() : NFBDefaultCoverImage();
  NSString *urlString = NFBProfileString(self.profile[key]); NSURL *url = [NSURL URLWithString:urlString]; if (!urlString.length || !url) return;
  NSUInteger generation = self.loadGeneration; __weak typeof(self) weakSelf = self;
  NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    UIImage *image = error ? nil : [UIImage imageWithData:data]; dispatch_async(dispatch_get_main_queue(), ^{
      typeof(self) self = weakSelf; if (!self || self.loadGeneration != generation || self.imageEdits[key] || ![NFBProfileString(self.profile[key]) isEqual:urlString]) return;
      if (image) target.image = image;
    });
  }]; self.imageTasks[key] = task; [task resume];
}
- (NSDictionary *)patch {
  NSMutableDictionary *patch = [NSMutableDictionary new]; NSDictionary *record = self.snapshot[@"value"];
  NSMutableDictionary *values = [NSMutableDictionary new]; for (NSString *key in self.fields) values[key] = self.fields[key].text ?: @"";
  values[@"description"] = self.bio.text ?: @""; values[@"com.nottwitter.birthDate"] = self.birthday ?: @"";
  for (NSString *key in values) {
    NSString *value = values[key];
    if ([value isEqual:NFBProfileString(record[key])]) continue;
    if ([key isEqual:@"website"]) value = NFBProfileNormalizedWebsite(value);
    if ([key isEqual:@"pronouns"]) value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![value isEqual:NFBProfileString(record[key])]) patch[key] = value.length ? (id)value : NSNull.null;
  }
  for (NSString *key in self.imageEdits) if (self.imageEdits[key] == NSNull.null) patch[key] = NSNull.null;
  return patch;
}
- (BOOL)hasChanges { return self.snapshot && ([self patch].count || self.imageEdits.count); }
- (void)changed {
  self.bioPlaceholder.hidden = self.bio.text.length > 0;
  self.navigationItem.rightBarButtonItem.enabled = !self.busy && [self hasChanges];
  self.modalInPresentation = self.busy || [self hasChanges]; self.navigationController.modalInPresentation = self.modalInPresentation;
  [self.view setNeedsLayout];
}
- (void)textViewDidChange:(UITextView *)textView { [self changed]; }
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)keyboardChanged:(NSNotification *)notification {
  CGRect frame = [self.view convertRect:[notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue] fromView:nil];
  CGRect overlap = CGRectIntersection(self.scroll.frame,frame); CGFloat bottom = CGRectIsNull(overlap) ? 0 : overlap.size.height;
  self.scroll.contentInset = UIEdgeInsetsMake(0,0,bottom,0); self.scroll.scrollIndicatorInsets = self.scroll.contentInset;
  UIView *focus = self.bio.isFirstResponder ? self.bio : nil; for (UITextField *field in self.fields.allValues) if (field.isFirstResponder) focus = field;
  if (focus) [self.scroll scrollRectToVisible:CGRectInset([focus convertRect:focus.bounds toView:self.scroll],0,-16) animated:YES];
}
- (void)cancel {
  if (self.busy && self.snapshot) return;
  if (![self hasChanges]) { [self dismissViewControllerAnimated:YES completion:nil]; return; }
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Discard changes?" message:@"Your profile changes haven’t been saved." preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Keep editing" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Discard" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self dismissViewControllerAnimated:YES completion:nil]; }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)presentationControllerDidAttemptToDismiss:(UIPresentationController *)presentationController { [self cancel]; }
- (void)showError:(NSError *)error reload:(BOOL)reload {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn’t update profile" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
  if (reload) [alert addAction:[UIAlertAction actionWithTitle:self.snapshot ? @"Discard edits and reload" : @"Retry" style:self.snapshot ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self loadProfile]; }]];
  [self presentViewController:alert animated:YES completion:nil];
}
- (void)save {
  if (self.busy || ![self hasChanges]) return; [self.view endEditing:YES];
  NSDictionary *patch = [self patch]; NSError *validation = NFBProfilePatchError(patch); if (validation) { [self showError:validation reload:NO]; return; }
  NSMutableDictionary *images = [NSMutableDictionary new]; for (NSString *key in self.imageEdits) if ([self.imageEdits[key] isKindOfClass:NSData.class]) images[key] = self.imageEdits[key];
  [self setWorking:YES]; __weak typeof(self) weakSelf = self;
  [self.service savePatch:patch images:images snapshot:self.snapshot completion:^(NSDictionary *snapshot, NSError *error) { dispatch_async(dispatch_get_main_queue(), ^{
    typeof(self) self = weakSelf; if (!self) return; [self setWorking:NO];
    if (error) { [self showError:error reload:[error.domain isEqual:@"NFBProfileEditor"] && (error.code == 6 || error.code == 3)]; return; }
    NSDictionary *updated = NFBProfileViewApplyingRecord(self.profile,snapshot[@"value"],snapshot[@"endpoint"]);
    // Only JSON values reach the persisted session; previews belong to this UI.
    if ([NFBAtprotoSession.sharedSession.did isEqual:self.service.accountDID]) [[NFBAtprotoClient sharedClient] acceptUpdatedProfile:updated];
    NSMutableDictionary *preview = [updated mutableCopy]; for (NSString *key in self.previewImages) preview[[@"_nfbLoaded" stringByAppendingString:key.capitalizedString]] = self.previewImages[key];
    self.snapshot = snapshot; [self.imageEdits removeAllObjects]; if (self.completion) self.completion(preview);
    [self dismissViewControllerAnimated:YES completion:nil];
  }); }];
}
- (void)updateBirthday {
  NSDateFormatter *f = [NSDateFormatter new]; f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; f.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; f.dateFormat = @"yyyy-MM-dd"; NSDate *date = [f dateFromString:self.birthday];
  f.locale = NSLocale.currentLocale; f.dateStyle = NSDateFormatterLongStyle; f.timeStyle = NSDateFormatterNoStyle;
  [self.birthdayButton setTitle:date ? [f stringFromDate:date] : @"Add your birth date" forState:UIControlStateNormal];
}
- (void)editBirthday {
  [self.view endEditing:YES]; NFBProfileBirthDateController *editor = [NFBProfileBirthDateController new]; editor.value = self.birthday;
  __weak typeof(self) weakSelf = self; editor.completion = ^(NSString *value) { weakSelf.birthday = value; [weakSelf updateBirthday]; [weakSelf changed]; }; [self.navigationController pushViewController:editor animated:YES];
}
- (void)editAvatar { [self pickPhoto:@"avatar"]; }
- (void)editBanner { [self pickPhoto:@"banner"]; }
- (void)pickPhoto:(NSString *)key {
  [self.view endEditing:YES]; self.pickingKey = key;
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  [sheet addAction:[UIAlertAction actionWithTitle:@"Choose existing photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init]; config.selectionLimit = 1; config.filter = PHPickerFilter.imagesFilter;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
  }]];
  if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) [sheet addAction:[UIAlertAction actionWithTitle:@"Take photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
    UIImagePickerController *picker = [UIImagePickerController new]; picker.sourceType = UIImagePickerControllerSourceTypeCamera; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
  }]];
  if (self.imageEdits[key] != NSNull.null && (self.snapshot[@"value"][key] || self.imageEdits[key])) [sheet addAction:[UIAlertAction actionWithTitle:@"Remove photo" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
    self.imageEdits[key] = NSNull.null; [self.previewImages removeObjectForKey:key]; [self.imageTasks[key] cancel];
    if ([key isEqual:@"avatar"]) self.avatar.image = NFBDefaultAvatarImage(); else self.banner.image = NFBDefaultCoverImage(); [self changed];
  }]];
  [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = [key isEqual:@"avatar"] ? self.avatarButton : self.bannerButton; sheet.popoverPresentationController.sourceRect = sheet.popoverPresentationController.sourceView.bounds;
  [self presentViewController:sheet animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
  NSString *key = [self.pickingKey copy];
  [picker dismissViewControllerAnimated:YES completion:^{
    if (!results.count) return; [self setWorking:YES];
    [results.firstObject.itemProvider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData *data, NSError *error) {
      UIImage *image = nil;
      if (data.length) {
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
        if (source) { CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES,(id)kCGImageSourceCreateThumbnailWithTransform:@YES,(id)kCGImageSourceThumbnailMaxPixelSize:@2048}); if (thumbnail) { image = [UIImage imageWithCGImage:thumbnail]; CGImageRelease(thumbnail); } CFRelease(source); }
      }
      dispatch_async(dispatch_get_main_queue(), ^{ [self setWorking:NO]; if (image) [self cropImage:image key:key]; else [self showError:error ?: [NSError errorWithDomain:@"NFBProfileEditor" code:4 userInfo:@{NSLocalizedDescriptionKey:@"That photo could not be opened. Choose another image."}] reload:NO]; });
    }];
  }];
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [picker dismissViewControllerAnimated:YES completion:nil]; }
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
  UIImage *image = info[UIImagePickerControllerOriginalImage]; NSString *key = [self.pickingKey copy];
  [picker dismissViewControllerAnimated:YES completion:^{ if (image) [self cropImage:image key:key]; }];
}
- (void)cropImage:(UIImage *)image key:(NSString *)key {
  NFBProfilePhotoCropController *crop = [NFBProfilePhotoCropController new]; crop.image = image; crop.banner = [key isEqual:@"banner"];
  __weak typeof(self) weakSelf = self; crop.completion = ^(UIImage *cropped) {
    typeof(self) self = weakSelf; if (!self) return;
    NSData *data = nil; for (CGFloat quality = 0.9; quality >= 0.3; quality -= 0.1) { data = UIImageJPEGRepresentation(cropped,quality); if (data.length <= 1000000) break; }
    if (!data.length || data.length > 1000000) { dispatch_async(dispatch_get_main_queue(), ^{ [self showError:[NSError errorWithDomain:@"NFBProfileEditor" code:4 userInfo:@{NSLocalizedDescriptionKey:@"That photo is too large. Choose a smaller image."}] reload:NO]; }); return; }
    self.imageEdits[key] = data; self.previewImages[key] = cropped; [self.imageTasks[key] cancel];
    if ([key isEqual:@"avatar"]) self.avatar.image = cropped; else self.banner.image = cropped; [self changed];
  };
  [self.navigationController pushViewController:crop animated:YES];
}
@end
