#import "NFBAdvancedSearchViewController.h"
#import "NFBTheme.h"

static NSArray<NSDictionary *> *NFBSearchConditions(void) {
  return @[
    @{@"key":@"words", @"name":@"All words", @"label":@"Contains all words:", @"placeholder":@"Enter search words"},
    @{@"key":@"phrase", @"name":@"Exact phrase", @"label":@"Contains exact phrase:", @"placeholder":@"Enter phrase"},
    @{@"key":@"any", @"name":@"Any words", @"label":@"Contains any words:", @"placeholder":@"Enter search words"},
    @{@"key":@"none", @"name":@"Without words", @"label":@"Does not contain words:", @"placeholder":@"Enter search words"},
    @{@"key":@"from", @"name":@"From accounts", @"label":@"From any accounts:", @"placeholder":@"Enter @usernames"},
    @{@"key":@"mentions", @"name":@"Mentioning", @"label":@"Mentioning any accounts:", @"placeholder":@"Enter @usernames"},
    @{@"key":@"tag", @"name":@"Hashtags", @"label":@"Contains any hashtags:", @"placeholder":@"Enter hashtags"},
    @{@"key":@"since", @"name":@"After date", @"label":@"Posted on or after:", @"placeholder":@"YYYY-MM-DD"},
    @{@"key":@"until", @"name":@"Before date", @"label":@"Posted on or before:", @"placeholder":@"YYYY-MM-DD"},
    @{@"key":@"min_faves", @"name":@"Like count", @"label":@"Minimum Like count:", @"placeholder":@"Enter count"},
    @{@"key":@"min_replies", @"name":@"Reply count", @"label":@"Minimum reply count:", @"placeholder":@"Enter count"},
    @{@"key":@"min_retweets", @"name":@"Retweet count", @"label":@"Minimum Retweet count:", @"placeholder":@"Enter count"},
    @{@"key":@"filter:follows", @"name":@"People I follow", @"label":@"Only from people I follow:", @"toggle":@YES},
    @{@"key":@"filter:links", @"name":@"Media and links", @"label":@"Contains media or links:", @"toggle":@YES},
    @{@"key":@"filter:replies", @"name":@"Replies", @"label":@"Only replies:", @"toggle":@YES}
  ];
}
@interface NFBAdvancedSearchViewController ()
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *conditions;
@end
@implementation NFBAdvancedSearchViewController
- (instancetype)initWithQuery:(NSString *)query {
  self = [super initWithStyle:UITableViewStylePlain];
  if (self) { NSMutableDictionary *first = [NFBSearchConditions().firstObject mutableCopy]; first[@"value"] = query ?: @""; _conditions = [NSMutableArray arrayWithObject:first]; }
  return self;
}
- (void)viewDidLoad {
  [super viewDidLoad]; self.title = @"Advanced Search";
  NFBIPAApplyTableViewAppearance(self.tableView); self.tableView.rowHeight = 84;
  self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Search" style:UIBarButtonItemStyleDone target:self action:@selector(submit)];
  UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem]; add.frame = CGRectMake(0, 0, 320, 60); add.tintColor = NFBColorAccent(); add.titleLabel.font = NFBFont(17, NFBFontWeightBold);
  [add setTitle:@"Add search condition" forState:UIControlStateNormal]; [add addTarget:self action:@selector(addCondition:) forControlEvents:UIControlEventTouchUpInside]; self.tableView.tableFooterView = add;
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.conditions.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSDictionary *condition = self.conditions[indexPath.row];
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
  cell.backgroundColor = NFBColorBackground(); cell.selectionStyle = UITableViewCellSelectionStyleNone;
  if ([condition[@"toggle"] boolValue]) {
    cell.textLabel.text = condition[@"label"]; cell.textLabel.textColor = NFBColorText(); cell.textLabel.font = NFBFont(17, NFBFontWeightRegular); cell.textLabel.numberOfLines = 0;
    UISwitch *toggle = [[UISwitch alloc] init]; toggle.onTintColor = NFBColorAccent(); toggle.on = [condition[@"value"] boolValue]; toggle.tag = indexPath.row;
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
  } else {
    UILabel *label = [[UILabel alloc] init]; label.translatesAutoresizingMaskIntoConstraints = NO; label.text = condition[@"label"]; label.textColor = NFBColorSecondaryText(); label.font = NFBFont(13, NFBFontWeightRegular);
    UITextField *field = [[UITextField alloc] init]; field.translatesAutoresizingMaskIntoConstraints = NO; NFBIPAApplySearchTextFieldAppearance(field, condition[@"placeholder"]);
    field.text = condition[@"value"]; field.tag = indexPath.row; field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo; field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.accessibilityLabel = condition[@"label"];
    if ([condition[@"key"] hasPrefix:@"min_"]) field.keyboardType = UIKeyboardTypeNumberPad;
    [field addTarget:self action:@selector(textChanged:) forControlEvents:UIControlEventEditingChanged];
    [cell.contentView addSubview:label]; [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16], [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12], [field.leadingAnchor constraintEqualToAnchor:label.leadingAnchor], [field.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16], [field.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:2], [field.heightAnchor constraintEqualToConstant:44]]];
  }
  return cell;
}
- (void)textChanged:(UITextField *)field { if (field.tag < (NSInteger)self.conditions.count) self.conditions[field.tag][@"value"] = field.text ?: @""; }
- (void)toggleChanged:(UISwitch *)toggle { if (toggle.tag < (NSInteger)self.conditions.count) self.conditions[toggle.tag][@"value"] = @(toggle.on); }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
  if (style == UITableViewCellEditingStyleDelete) { [self.view endEditing:YES]; [self.conditions removeObjectAtIndex:path.row]; [tableView reloadData]; }
}
- (void)addCondition:(UIButton *)sender {
  [self.view endEditing:YES];
  UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Add search condition" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  for (NSDictionary *condition in NFBSearchConditions()) {
    [menu addAction:[UIAlertAction actionWithTitle:condition[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
      NSMutableDictionary *row = [condition mutableCopy]; row[@"value"] = [condition[@"toggle"] boolValue] ? @YES : @"";
      [self.conditions addObject:row]; [self.tableView reloadData]; [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.conditions.count - 1 inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    }]];
  }
  [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  menu.popoverPresentationController.sourceView = sender; menu.popoverPresentationController.sourceRect = sender.bounds;
  [self presentViewController:menu animated:YES completion:nil];
}
- (void)showError:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Check your search" message:message preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)submit {
  [self.view endEditing:YES]; NSMutableArray *parts = [NSMutableArray array];
  NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init]; dateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0]; dateFormatter.dateFormat = @"yyyy-MM-dd"; dateFormatter.lenient = NO;
  for (NSDictionary *condition in self.conditions) {
    NSString *key = condition[@"key"];
    if ([condition[@"toggle"] boolValue]) { if ([condition[@"value"] boolValue]) [parts addObject:key]; continue; }
    NSString *value = [condition[@"value"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!value.length) continue;
    if ([key isEqualToString:@"words"]) { [parts addObject:value]; continue; }
    if ([key isEqualToString:@"phrase"]) { value = [[value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""]; [parts addObject:[NSString stringWithFormat:@"\"%@\"", value]]; continue; }
    if ([key isEqualToString:@"since"] || [key isEqualToString:@"until"]) {
      NSDate *date = [dateFormatter dateFromString:value];
      if (!date || ![[dateFormatter stringFromDate:date] isEqualToString:value]) { [self showError:@"Enter dates as YYYY-MM-DD."]; return; }
      // The reference's end-date control is inclusive; the API's until is exclusive.
      if ([key isEqualToString:@"until"]) value = [dateFormatter stringFromDate:[date dateByAddingTimeInterval:86400]];
      [parts addObject:[NSString stringWithFormat:@"%@:%@", key, value]]; continue;
    }
    if ([key hasPrefix:@"min_"] && [value rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) { [self showError:@"Enter a whole number for minimum counts."]; return; }
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *word in [value componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if (word.length) [words addObject:word];
    if ([key isEqualToString:@"any"]) [parts addObject:[NSString stringWithFormat:@"(%@)", [words componentsJoinedByString:@" OR "]]];
    else for (NSString *word in words) [parts addObject:[key isEqualToString:@"none"] ? [@"-" stringByAppendingString:word] : [NSString stringWithFormat:@"%@:%@", key, word]];
  }
  NSString *query = [parts componentsJoinedByString:@" "];
  if (!query.length) { [self showError:@"Add a search condition first."]; return; }
  [self dismissViewControllerAnimated:YES completion:^{ if (self.search) self.search(query); }];
}
@end
