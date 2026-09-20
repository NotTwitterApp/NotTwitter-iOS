#import "NFBArticleReaderView.h"
#import "NFBTheme.h"
#import <WebKit/WebKit.h>

@interface NFBArticleMessageRelay : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) NFBArticleReaderView *owner;
@end
@interface NFBArticleReaderView () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, copy) NSDictionary *article;
@property (nonatomic, copy) NSString *canonicalHTML;
@property (nonatomic, copy) NSString *pendingHTML;
@property (nonatomic, assign) BOOL pendingProxy;
@property (nonatomic, strong) NSURLSessionDataTask *htmlTask;
@property (nonatomic, assign) NSUInteger generation;
@property (nonatomic, assign) BOOL ready;
@property (nonatomic, readwrite) CGFloat contentHeight;
- (void)receiveHeight:(CGFloat)height;
@end
@implementation NFBArticleMessageRelay
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
  if ([message.body respondsToSelector:@selector(doubleValue)]) [self.owner receiveHeight:[message.body doubleValue]];
}
@end
@implementation NFBArticleReaderView
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    NFBArticleMessageRelay *relay = [[NFBArticleMessageRelay alloc] init];
    relay.owner = self;
    [configuration.userContentController addScriptMessageHandler:relay name:@"articleHeight"];
    NSString *compatibility = @"if(!Array.prototype.at)Object.defineProperty(Array.prototype,'at',{value:function(n){n=Math.trunc(n)||0;return this[n<0?this.length+n:n];}});";
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:compatibility injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];
    for (NSString *name in @[@"nfb-marked-15.0.12", @"nfb-article-reader"]) {
      NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"js"];
      NSString *script = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
      if (script) [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:script injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    }
    NSString *bridge = @"window.nfbRender=(a,h,tryOnly)=>{const r=NFBArticle.render(a,h);const el=document.getElementById('body');if((!tryOnly||r.usable)&&el.innerHTML!==r.html)el.innerHTML=r.html;if(!el.textContent&&!el.querySelector('img'))el.textContent='The article could not be loaded. It will retry automatically, or you can read it on the website.';nfbMeasure();return r.usable;};window.nfbMeasure=()=>{const el=document.getElementById('body'),rect=el.getBoundingClientRect(),zoom=parseFloat(getComputedStyle(el).zoom)||1;window.webkit.messageHandlers.articleHeight.postMessage(Math.ceil(Math.max(rect.height,el.scrollHeight*zoom))+2);};new ResizeObserver(nfbMeasure).observe(document.getElementById('body'));document.addEventListener('load',nfbMeasure,true);document.fonts.ready.then(nfbMeasure);document.fonts.addEventListener('loadingdone',nfbMeasure);";
    [configuration.userContentController addUserScript:[[WKUserScript alloc] initWithSource:bridge injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES]];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.navigationDelegate = self;
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.opaque = NO;
    self.webView.backgroundColor = UIColor.clearColor;
    self.webView.scrollView.scrollEnabled = NO;
    // The outer Tweet scroller owns safe areas. Automatic WKWebView insets
    // otherwise reduce the visible body without being included in its JS height.
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.scrollView.contentInset = UIEdgeInsetsZero;
    self.webView.scrollView.bounces = NO;
    self.webView.scrollView.backgroundColor = UIColor.clearColor;
    [self addSubview:self.webView];
    self.contentHeight = 32;
    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:self.contentHeight];
    [NSLayoutConstraint activateConstraints:@[self.heightConstraint,
      [self.webView.topAnchor constraintEqualToAnchor:self.topAnchor],
      [self.webView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
      [self.webView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
      [self.webView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor]]];
    NSString *html = @"<!doctype html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'><meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; img-src https: http:; style-src 'unsafe-inline'; font-src data:; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\"><style>html,body{margin:0;padding:0;background:transparent;color:var(--text);font:17px/1.5 NFBChirp,-apple-system;overflow-wrap:anywhere;-webkit-text-size-adjust:100%}#body{display:flow-root;margin:0;padding-bottom:8px}p,div,ul,ol,dl,pre,blockquote,figure,table{margin:0 0 16px}span div,li p{margin-bottom:4px}h1,h2,h3,h4,h5,h6{font-weight:700;line-height:1.25;margin:22px 0 12px}h1{font-size:25px}h2{font-size:22px}h3{font-size:19px}h4,h5,h6{font-size:17px}a{color:var(--accent);text-decoration:underline}img{max-width:100%;height:auto;border-radius:8px;display:block}figure{margin-left:0;margin-right:0}figcaption,small{font-size:14px;color:var(--secondary)}blockquote{border-left:3px solid var(--accent);padding-left:12px;margin-left:0;margin-right:0;color:var(--secondary)}pre{overflow-x:auto;white-space:pre;padding:12px;background:var(--elevated);border-radius:8px}code{font:14px/1.5 ui-monospace,Menlo,monospace;background:var(--elevated)}ul,ol{padding-left:26px}li{margin-bottom:6px}table{display:block;max-width:100%;overflow-x:auto;border-collapse:collapse}th,td{border:1px solid var(--border);padding:6px;min-width:60px}mark{background:#ffe58a;color:#14171a}hr{border:0;border-top:1px solid var(--border);margin:18px 0}#body>:last-child{margin-bottom:0}</style></head><body><div id='body'></div></body></html>";
    static NSString *fontCSS;
    static dispatch_once_t fontToken;
    dispatch_once(&fontToken, ^{
      NSMutableString *styles = [NSMutableString string];
      for (NSString *weight in @[@"Regular", @"Bold"]) {
        NSString *name = [@"Chirp-" stringByAppendingString:weight];
        NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"otf" inDirectory:@"Chirp"];
        NSString *encoded = [[NSData dataWithContentsOfFile:path] base64EncodedStringWithOptions:0];
        if (encoded) [styles appendFormat:@"@font-face{font-family:NFBChirp;font-weight:%@;src:url(data:font/otf;base64,%@)}", [weight isEqualToString:@"Bold"] ? @"700" : @"400", encoded];
      }
      fontCSS = [styles copy];
    });
    html = [html stringByReplacingOccurrencesOfString:@"</style>" withString:[fontCSS stringByAppendingString:@"</style>"]];
    [self.webView loadHTMLString:html baseURL:nil];
  }
  return self;
}
- (void)dealloc { [self.htmlTask cancel]; }
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, self.contentHeight); }
- (void)receiveHeight:(CGFloat)height {
  if (!isfinite(height) || height < 0) return;
  height = MAX(1, ceil(height));
  if (fabs(height - self.contentHeight) < 0.5) return;
  self.contentHeight = height;
  self.heightConstraint.constant = height;
  [self invalidateIntrinsicContentSize];
  if (self.heightDidChange) self.heightDidChange();
}
- (void)refresh { if (self.article) [self displayArticle:self.article]; }
- (void)displayArticle:(NSDictionary *)article {
  BOOL changed = ![self.article[@"url"] isEqual:article[@"url"]] ||
    (article[@"revision"] && ![self.article[@"revision"] isEqual:article[@"revision"]]);
  if (changed) self.canonicalHTML = nil;
  self.pendingHTML = nil;
  self.article = article;
  self.generation++;
  [self.htmlTask cancel];
  // Keep a successful body while revalidating the same revision.
  if (self.ready) [self renderWithCompletion:nil];
  [self fetchCanonicalUsingProxy:NO generation:self.generation];
}
- (void)renderWithCompletion:(void (^)(BOOL))completion {
  if (!self.ready || !self.article) { if (completion) completion(NO); return; }
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[self.article, self.canonicalHTML ?: @""] options:0 error:nil];
  NSString *args = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  if (!args) return;
  NSString *script = [NSString stringWithFormat:@"window.nfbRender.apply(null,%@)", args];
  [self.webView evaluateJavaScript:script completionHandler:^(id result, NSError *error) {
    if (completion) completion(!error && [result respondsToSelector:@selector(boolValue)] && [result boolValue]);
  }];
}
- (void)fetchCanonicalUsingProxy:(BOOL)proxy generation:(NSUInteger)generation {
  NSString *source = [self.article[@"url"] isKindOfClass:NSString.class] ? self.article[@"url"] : @"";
  NSURL *sourceURL = [NSURL URLWithString:source];
  if (!sourceURL.host.length || ![@[@"https", @"http"] containsObject:sourceURL.scheme.lowercaseString]) return;
  NSURL *url = proxy ? [NSURL URLWithString:[@"https://r.jina.ai/" stringByAppendingString:source]] : sourceURL;
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:10];
  [request setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
  [request setValue:proxy ? @"text/plain" : @"text/html,application/xhtml+xml" forHTTPHeaderField:@"Accept"];
  request.HTTPShouldHandleCookies = NO;
  __weak typeof(self) weakSelf = self;
  self.htmlTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    NSString *html = !error && status >= 200 && status < 300 ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) self = weakSelf;
      if (!self || generation != self.generation) return;
      if (html.length == 0) { if (!proxy) [self fetchCanonicalUsingProxy:YES generation:generation]; return; }
      if (!self.ready) { self.pendingHTML = html; self.pendingProxy = proxy; return; }
      [self tryCanonicalHTML:html proxy:proxy generation:generation];
    });
  }];
  [self.htmlTask resume];
}
- (void)tryCanonicalHTML:(NSString *)html proxy:(BOOL)proxy generation:(NSUInteger)generation {
  NSData *data = [NSJSONSerialization dataWithJSONObject:@[self.article ?: @{}, html, @YES] options:0 error:nil];
  NSString *args = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  [self.webView evaluateJavaScript:[NSString stringWithFormat:@"window.nfbRender.apply(null,%@)", args] completionHandler:^(id result, NSError *error) {
    if (generation != self.generation) return;
    BOOL usable = !error && [result respondsToSelector:@selector(boolValue)] && [result boolValue];
    if (usable) self.canonicalHTML = html;
    else if (!proxy) [self fetchCanonicalUsingProxy:YES generation:generation];
  }];
}

static NSString *NFBCSSColor(UIColor *color) {
  CGFloat r=0,g=0,b=0,a=1;
  [color getRed:&r green:&g blue:&b alpha:&a];
  return [NSString stringWithFormat:@"rgba(%.0f,%.0f,%.0f,%.3f)",r*255,g*255,b*255,a];
}
- (void)applyTheme {
  if (!self.ready) return;
  NSDictionary *colors = @{@"--text":NFBCSSColor(NFBColorText()), @"--secondary":NFBCSSColor(NFBColorSecondaryText()), @"--accent":NFBCSSColor(NFBColorAccent()), @"--elevated":NFBCSSColor(NFBColorElevatedBackground()), @"--border":NFBCSSColor(NFBColorBorder()), @"--font-scale":[NSString stringWithFormat:@"%.3f", NFBCurrentFontScale()]};
  NSData *data = [NSJSONSerialization dataWithJSONObject:colors options:0 error:nil];
  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  [self.webView evaluateJavaScript:[NSString stringWithFormat:@"Object.entries(%@).forEach(([k,v])=>document.documentElement.style.setProperty(k,v));document.getElementById('body').style.zoom=getComputedStyle(document.documentElement).getPropertyValue('--font-scale');nfbMeasure();", json] completionHandler:nil];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  self.ready = YES;
  [self applyTheme];
  [self renderWithCompletion:nil];
  if (self.pendingHTML) {
    NSString *html = self.pendingHTML;
    self.pendingHTML = nil;
    [self tryCanonicalHTML:html proxy:self.pendingProxy generation:self.generation];
  }
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  NSURL *url = action.request.URL;
  if ([url.absoluteString isEqualToString:@"about:blank"]) { decisionHandler(WKNavigationActionPolicyAllow); return; }
  if (action.navigationType == WKNavigationTypeLinkActivated && [@[@"https", @"http"] containsObject:url.scheme.lowercaseString] && self.openURL) self.openURL(url);
  decisionHandler(WKNavigationActionPolicyCancel);
}
@end
