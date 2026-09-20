#import "NFBBlueskyLoginViewController.h"
#import "NFBAtprotoSession.h"
#import "NFBTheme.h"
#import <SafariServices/SafariServices.h>

@interface NFBBlueskyLoginViewController () <UITextFieldDelegate, SFSafariViewControllerDelegate>
@property (nonatomic, strong) UITextField *identifierField;
@property (nonatomic, strong) UIButton *signInButton;
@property (nonatomic, strong) UIButton *forgotButton;
@property (nonatomic, strong) UIImageView *spinner;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) SFSafariViewController *safariViewController;
@property (nonatomic, assign) BOOL oauthCallbackReceived;
@property (nonatomic, assign) NSUInteger safariCloseGraceGeneration;
@property (nonatomic, assign) BOOL addAccountMode;
@end

@implementation NFBBlueskyLoginViewController

- (instancetype)initWithAddAccountMode:(BOOL)addAccountMode {
    self = [super init];
    if (self) {
        _addAccountMode = addAccountMode;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = NFBColorBackground();
    self.title = self.addAccountMode ? @"Add account" : @"Not Twitter";
    if (@available(iOS 13.0, *)) {
        self.modalInPresentation = !self.addAccountMode;
    }

    if (self.addAccountMode) {
        [self installCancelButton];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(oauthCallbackReceived:)
                                                 name:NFBAtprotoOAuthCallbackReceivedNotification
                                               object:[NFBAtprotoSession sharedSession]];
    [self buildLoginForm];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!self.addAccountMode) {
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (!self.addAccountMode) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
}

- (void)installCancelButton {
    if (!self.addAccountMode) {
        self.navigationItem.rightBarButtonItem = nil;
        return;
    }
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                            target:self
                                                                                            action:@selector(cancelTapped)];
}

- (void)buildLoginForm {
    UIImageView *logoView = [[UIImageView alloc] initWithImage:NFBTemplateIcon(@"nfb_twitter_logo")];
    logoView.translatesAutoresizingMaskIntoConstraints = NO;
    logoView.tintColor = NFBColorAccent();
    logoView.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = self.addAccountMode ? @"Add an existing account" : @"Log in to Not Twitter";
    titleLabel.textColor = NFBColorText();
    titleLabel.font = NFBFont(31.0, NFBFontWeightHeavy);
    titleLabel.adjustsFontForContentSizeCategory = YES;
    titleLabel.numberOfLines = 0;

    self.identifierField = [self configuredTextFieldWithPlaceholder:@"Phone, email or username"];
    self.identifierField.translatesAutoresizingMaskIntoConstraints = NO;
    self.identifierField.textContentType = UITextContentTypeUsername;
    self.identifierField.keyboardType = UIKeyboardTypeEmailAddress;
    self.identifierField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.identifierField.autocorrectionType = UITextAutocorrectionTypeNo;

    self.signInButton = [NFBPillButton buttonWithType:UIButtonTypeSystem];
    self.signInButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.signInButton setTitle:@"Log in" forState:UIControlStateNormal];
    NFBIPAApplyButtonAppearance(self.signInButton, NFBIPAButtonStylePrimary, NFBIPAButtonSizeLarge);
    [self.signInButton addTarget:self action:@selector(signInTapped) forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIImageView alloc] initWithImage:NFBLoadingImage()];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    self.spinner.tintColor = NFBColorSecondaryText();
    self.spinner.contentMode = UIViewContentModeScaleAspectFit;
    self.spinner.hidden = YES;

    self.forgotButton = [NFBPillButton buttonWithType:UIButtonTypeSystem];
    self.forgotButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.forgotButton setTitle:@"Forgot password?" forState:UIControlStateNormal];
    NFBIPAApplyButtonAppearance(self.forgotButton, NFBIPAButtonStyleText, NFBIPAButtonSizeCompact);
    self.forgotButton.titleLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    self.forgotButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    self.forgotButton.contentEdgeInsets = UIEdgeInsetsZero;
    [self.forgotButton addTarget:self action:@selector(forgotTapped) forControlEvents:UIControlEventTouchUpInside];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.errorLabel.font = NFBFont(14.0, NFBFontWeightRegular);
    self.errorLabel.textColor = [UIColor systemRedColor];
    self.errorLabel.numberOfLines = 0;

    UILabel *footerLabel = [[UILabel alloc] init];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.font = NFBFont(15.0, NFBFontWeightRegular);
    footerLabel.numberOfLines = 0;
    footerLabel.userInteractionEnabled = YES;
    NSString *footerText = @"Don't have an account? Sign up";
    NSMutableAttributedString *footer = [[NSMutableAttributedString alloc] initWithString:footerText
                                                                               attributes:@{NSForegroundColorAttributeName: NFBColorSecondaryText(),
                                                                                            NSFontAttributeName: NFBFont(15.0, NFBFontWeightRegular)}];
    NSRange signUpRange = [footerText rangeOfString:@"Sign up"];
    if (signUpRange.location != NSNotFound) {
        [footer addAttribute:NSForegroundColorAttributeName value:NFBColorAccent() range:signUpRange];
    }
    footerLabel.attributedText = footer;
    [footerLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(signUpTapped)]];

    [self.view addSubview:logoView];
    [self.view addSubview:titleLabel];
    [self.view addSubview:self.identifierField];
    [self.view addSubview:self.signInButton];
    [self.view addSubview:self.spinner];
    [self.view addSubview:self.forgotButton];
    [self.view addSubview:self.errorLabel];
    [self.view addSubview:footerLabel];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [logoView.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [logoView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:self.addAccountMode ? 22.0 : 18.0],
        [logoView.widthAnchor constraintEqualToConstant:35.0],
        [logoView.heightAnchor constraintEqualToConstant:35.0],

        [titleLabel.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:32.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-32.0],
        [titleLabel.topAnchor constraintEqualToAnchor:logoView.bottomAnchor constant:self.addAccountMode ? 48.0 : 74.0],

        [self.identifierField.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.identifierField.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.identifierField.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:32.0],
        [self.identifierField.heightAnchor constraintEqualToConstant:58.0],

        [self.signInButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.signInButton.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.signInButton.topAnchor constraintEqualToAnchor:self.identifierField.bottomAnchor constant:24.0],
        [self.signInButton.heightAnchor constraintEqualToConstant:50.0],

        [self.spinner.centerYAnchor constraintEqualToAnchor:self.signInButton.centerYAnchor],
        [self.spinner.trailingAnchor constraintEqualToAnchor:self.signInButton.trailingAnchor constant:-18.0],

        [self.forgotButton.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.forgotButton.trailingAnchor constraintLessThanOrEqualToAnchor:titleLabel.trailingAnchor],
        [self.forgotButton.topAnchor constraintEqualToAnchor:self.signInButton.bottomAnchor constant:16.0],
        [self.forgotButton.heightAnchor constraintGreaterThanOrEqualToConstant:32.0],

        [self.errorLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.errorLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [self.errorLabel.topAnchor constraintEqualToAnchor:self.forgotButton.bottomAnchor constant:12.0],

        [footerLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [footerLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],
        [footerLabel.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-24.0]
    ]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (UITextField *)configuredTextFieldWithPlaceholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] init];
    field.placeholder = placeholder;
    field.delegate = self;
    NFBIPAApplyLegacyFormTextFieldAppearance(field, placeholder, NO);
    UIView *left = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 15.0, 56.0)];
    field.leftView = left;
    field.leftViewMode = UITextFieldViewModeAlways;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyGo;
    field.adjustsFontForContentSizeCategory = YES;
    return field;
}

- (void)cancelTapped {
    [[NFBAtprotoSession sharedSession] cancelPendingOAuthSignIn];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)signInTapped {
    NSString *identifier = [self.identifierField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (identifier.length == 0) {
        [self showError:@"Enter your phone, email or username."];
        return;
    }
    self.oauthCallbackReceived = NO;
    self.safariCloseGraceGeneration++;
    [self showStatus:@""];
    [self.view endEditing:YES];
    [self setLoading:YES];

    __weak typeof(self) weakSelf = self;
    [[NFBAtprotoSession sharedSession] signInWithIdentifier:identifier
                                    authorizationURLHandler:^(NSURL *authorizationURL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:authorizationURL];
            safari.delegate = strongSelf;
            strongSelf.safariViewController = safari;
            [strongSelf presentViewController:safari animated:YES completion:nil];
        });
    } completion:^(BOOL success, NSDictionary *session, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf setLoading:NO];
            if (success) {
                [strongSelf.safariViewController dismissViewControllerAnimated:YES completion:nil];
                [strongSelf dismissViewControllerAnimated:YES completion:nil];
            } else {
                [strongSelf installCancelButton];
                [strongSelf showError:[strongSelf displayMessageForSignInError:error.localizedDescription ?: @"Unable to sign in."]];
            }
        });
    }];
}

- (void)oauthCallbackReceived:(NSNotification *)notification {
    self.oauthCallbackReceived = YES;
    self.safariCloseGraceGeneration++;
    self.navigationItem.rightBarButtonItem = nil;
    [self showStatus:@"Finishing sign-in..."];
    [self setLoading:YES];
    if (self.safariViewController) {
        [self.safariViewController dismissViewControllerAnimated:YES completion:nil];
        self.safariViewController = nil;
    }
}

- (void)setLoading:(BOOL)loading {
    self.signInButton.enabled = !loading;
    self.identifierField.enabled = !loading;
    self.forgotButton.enabled = !loading;
    self.signInButton.alpha = loading ? 0.70 : 1.0;
    if (loading) {
        NFBStartLoadingAnimation(self.spinner);
    } else {
        NFBStopLoadingAnimation(self.spinner);
        self.spinner.hidden = YES;
    }
}

- (void)showStatus:(NSString *)message {
    self.errorLabel.textColor = NFBColorSecondaryText();
    self.errorLabel.text = message ?: @"";
}

- (void)showError:(NSString *)message {
    self.errorLabel.textColor = [UIColor systemRedColor];
    self.errorLabel.text = message ?: @"";
}

- (NSString *)displayMessageForSignInError:(NSString *)message {
    if (message.length == 0) return @"Unable to sign in.";
    NSMutableString *displayMessage = [message mutableCopy];
    [displayMessage replaceOccurrencesOfString:@"Bluesky OAuth"
                                    withString:@"sign-in"
                                       options:0
                                         range:NSMakeRange(0, displayMessage.length)];
    [displayMessage replaceOccurrencesOfString:@"Bluesky"
                                    withString:@"Not Twitter"
                                       options:0
                                         range:NSMakeRange(0, displayMessage.length)];
    [displayMessage replaceOccurrencesOfString:@"OAuth"
                                    withString:@"sign-in"
                                       options:0
                                         range:NSMakeRange(0, displayMessage.length)];
    [displayMessage replaceOccurrencesOfString:@"handle or DID"
                                    withString:@"username"
                                       options:0
                                         range:NSMakeRange(0, displayMessage.length)];
    return displayMessage;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self signInTapped];
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    NFBIPAApplyLegacyFormTextFieldAppearance(textField, textField.placeholder, YES);
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    NFBIPAApplyLegacyFormTextFieldAppearance(textField, textField.placeholder, NO);
}

- (void)forgotTapped {
    [self.identifierField becomeFirstResponder];
    [self showStatus:@"Enter your username to continue."];
}

- (void)signUpTapped {
    [self.identifierField becomeFirstResponder];
    [self showStatus:@"Enter your username to continue."];
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    self.safariViewController = nil;
    if (![[NFBAtprotoSession sharedSession] hasSession]) {
        if (self.oauthCallbackReceived || [[NFBAtprotoSession sharedSession] hasReceivedPendingOAuthCallback]) {
            [self showStatus:@"Finishing sign-in..."];
            [self setLoading:YES];
            return;
        }
        if ([[NFBAtprotoSession sharedSession] hasPendingOAuthSignIn]) {
            [self waitForOAuthCallbackAfterSafariClose];
            return;
        }
        [[NFBAtprotoSession sharedSession] cancelPendingOAuthSignIn];
        [self setLoading:NO];
        [self showError:@"Sign-in was cancelled."];
    }
}

- (void)waitForOAuthCallbackAfterSafariClose {
    self.navigationItem.rightBarButtonItem = nil;
    [self showStatus:@"Waiting for sign-in to finish..."];
    [self setLoading:YES];

    self.safariCloseGraceGeneration++;
    NSUInteger generation = self.safariCloseGraceGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.safariCloseGraceGeneration != generation) return;
        if ([[NFBAtprotoSession sharedSession] hasSession]) return;
        if (strongSelf.oauthCallbackReceived || [[NFBAtprotoSession sharedSession] hasReceivedPendingOAuthCallback]) {
            [strongSelf showStatus:@"Finishing sign-in..."];
            [strongSelf setLoading:YES];
            return;
        }
        if ([[NFBAtprotoSession sharedSession] hasPendingOAuthSignIn]) {
            [[NFBAtprotoSession sharedSession] cancelPendingOAuthSignIn];
        }
        [strongSelf installCancelButton];
        [strongSelf setLoading:NO];
        [strongSelf showError:@"Sign-in was cancelled."];
    });
}

@end

UIViewController *NFBTopMostViewController(void) {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) {
        controller = controller.presentedViewController;
    }
    if ([controller isKindOfClass:[UINavigationController class]]) {
        controller = [(UINavigationController *)controller visibleViewController];
    }
    if ([controller isKindOfClass:[UITabBarController class]]) {
        controller = [(UITabBarController *)controller selectedViewController];
    }
    return controller;
}

void NFBPresentBlueskyLoginIfNeeded(void) {
    if ([[NFBAtprotoSession sharedSession] hasSession]) return;
    if ([[NFBAtprotoSession sharedSession] hasPendingOAuthSignIn]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[NFBAtprotoSession sharedSession] hasSession]) return;
        if ([[NFBAtprotoSession sharedSession] hasPendingOAuthSignIn]) return;
        UIViewController *top = NFBTopMostViewController();
        if (!top || [top isKindOfClass:[NFBBlueskyLoginViewController class]]) return;
        if ([top isKindOfClass:[UINavigationController class]] &&
            [[(UINavigationController *)top topViewController] isKindOfClass:[NFBBlueskyLoginViewController class]]) return;

        NFBBlueskyLoginViewController *login = [[NFBBlueskyLoginViewController alloc] init];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:login];
        NFBApplyNavigationAppearance(nav);
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        if (@available(iOS 13.0, *)) {
            nav.modalInPresentation = YES;
        }
        [top presentViewController:nav animated:YES completion:nil];
    });
}

void NFBPresentBlueskyAddAccount(void) {
    if ([[NFBAtprotoSession sharedSession] hasPendingOAuthSignIn]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([[NFBAtprotoSession sharedSession] hasPendingOAuthSignIn]) return;
        UIViewController *top = NFBTopMostViewController();
        if (!top || [top isKindOfClass:[NFBBlueskyLoginViewController class]]) return;
        if ([top isKindOfClass:[UINavigationController class]] &&
            [[(UINavigationController *)top topViewController] isKindOfClass:[NFBBlueskyLoginViewController class]]) return;

        NFBBlueskyLoginViewController *login = [[NFBBlueskyLoginViewController alloc] initWithAddAccountMode:YES];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:login];
        NFBApplyNavigationAppearance(nav);
        nav.modalPresentationStyle = UIModalPresentationFormSheet;
        [top presentViewController:nav animated:YES completion:nil];
    });
}
