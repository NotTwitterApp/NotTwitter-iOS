#import "NFBSearchOptions.h"
#import "NFBAtprotoSession.h"
#import "NFBTheme.h"

NSArray<NSString *> *NFBSearchTabTitles(void) { return @[@"Top", @"Latest", @"People", @"Photos", @"Videos"]; }
static NSString *NFBSearchDefaultsKey(NSString *name) {
  return [NSString stringWithFormat:@"NFBSearch:%@:%@", [NFBAtprotoSession sharedSession].did ?: @"anonymous", name];
}
NSArray<NSString *> *NFBSavedSearches(void) {
  NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:NFBSearchDefaultsKey(@"saved")];
  NSMutableArray *queries = [NSMutableArray array];
  for (id query in stored) if ([query isKindOfClass:NSString.class] && [query length] && ![queries containsObject:query]) [queries addObject:query];
  return queries;
}
void NFBSetSearchSaved(NSString *query, BOOL saved) {
  query = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  if (!query.length) return;
  NSMutableArray *queries = [NFBSavedSearches() mutableCopy];
  [queries removeObject:query];
  if (saved) [queries addObject:query];
  [NSUserDefaults.standardUserDefaults setObject:queries forKey:NFBSearchDefaultsKey(@"saved")];
}
static BOOL NFBSearchSetting(NSString *name) {
  id value = [NSUserDefaults.standardUserDefaults objectForKey:NFBSearchDefaultsKey(name)];
  return value ? [value boolValue] : YES;
}
BOOL NFBSearchHidesSensitiveContent(void) { return NFBSearchSetting(@"hideSensitive"); }
BOOL NFBSearchExcludesMutedAccounts(void) { return NFBSearchSetting(@"excludeMuted"); }

@interface NFBSearchOptionsViewController ()
@property (nonatomic) BOOL settings;
@property (nonatomic) BOOL originalFollowingOnly;
@property (nonatomic) NSUInteger accountGeneration;
@end
@implementation NFBSearchOptionsViewController
- (instancetype)initWithSettings:(BOOL)settings {
  self = [super initWithStyle:UITableViewStylePlain];
  if (self) { _settings = settings; _accountGeneration = [NFBAtprotoSession sharedSession].accountGeneration; }
  return self;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.originalFollowingOnly = self.followingOnly;
  self.title = self.settings ? @"Search settings" : @"Search filters";
  NFBIPAApplyTableViewAppearance(self.tableView);
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.rowHeight = 52.0;
  self.tableView.sectionHeaderHeight = 52.0;
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:self.settings ? @"Done" : @"Cancel" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
  if (!self.settings) {
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Apply" style:UIBarButtonItemStyleDone target:self action:@selector(apply)];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 168)];
    UIStackView *actions = [[UIStackView alloc] initWithFrame:footer.bounds]; actions.autoresizingMask = UIViewAutoresizingFlexibleWidth; actions.axis = UILayoutConstraintAxisVertical; actions.distribution = UIStackViewDistributionFillEqually;
    for (NSInteger index = 0; index < 3; index++) {
      UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; button.tag = index;
      button.titleLabel.font = NFBFont(17, NFBFontWeightRegular); button.tintColor = NFBColorAccent();
      [button setTitle:index == 0 ? ([NFBSavedSearches() containsObject:self.query] ? @"Remove from saved search" : @"Save search") : (index == 1 ? @"Search settings" : @"Advanced Search") forState:UIControlStateNormal];
      [button addTarget:self action:@selector(footerAction:) forControlEvents:UIControlEventTouchUpInside]; [actions addArrangedSubview:button];
    }
    [footer addSubview:actions]; self.tableView.tableFooterView = footer;
  }
}
- (void)footerAction:(UIButton *)button {
  if (self.accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) { [self cancel]; return; }
  if (button.tag == 0) {
    BOOL saved = [NFBSavedSearches() containsObject:self.query]; NFBSetSearchSaved(self.query, !saved);
    [button setTitle:saved ? @"Save search" : @"Remove from saved search" forState:UIControlStateNormal];
  } else {
    [self dismissViewControllerAnimated:YES completion:^{ if (button.tag == 1) { if (self.openSettings) self.openSettings(); } else if (self.openAdvancedSearch) self.openAdvancedSearch(); }];
  }
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)apply {
  if (self.accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) { [self cancel]; return; }
  if (self.applyFilters) self.applyFilters(self.followingOnly);
  [self cancel];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.settings ? 1 : 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return self.settings ? CGFLOAT_MIN : 52; }
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
  if (self.settings) return nil;
  UIView *header = [[UIView alloc] init]; header.backgroundColor = NFBColorBackground();
  UILabel *label = [[UILabel alloc] init]; label.translatesAutoresizingMaskIntoConstraints = NO;
  label.text = section == 0 ? @"People" : @"Location"; label.font = NFBFont(20, NFBFontWeightHeavy); label.textColor = NFBColorText();
  [header addSubview:label];
  [NSLayoutConstraint activateConstraints:@[[label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:16], [label.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]]];
  return header;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
  cell.backgroundColor = NFBColorBackground(); cell.textLabel.font = NFBFont(17, NFBFontWeightRegular); cell.textLabel.textColor = NFBColorText(); cell.tintColor = NFBColorAccent();
  cell.detailTextLabel.font = NFBFont(13, NFBFontWeightRegular); cell.detailTextLabel.textColor = NFBColorSecondaryText(); cell.detailTextLabel.numberOfLines = 0;
  if (self.settings) {
    cell.textLabel.text = indexPath.row == 0 ? @"Hide sensitive content" : @"Remove blocked and muted accounts";
    cell.textLabel.numberOfLines = 0;
    UISwitch *toggle = [[UISwitch alloc] init]; toggle.tag = indexPath.row; toggle.onTintColor = NFBColorAccent();
    toggle.on = indexPath.row == 0 ? NFBSearchHidesSensitiveContent() : NFBSearchExcludesMutedAccounts();
    [toggle addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
  } else {
    BOOL selected = indexPath.section == 0 ? (indexPath.row == (self.followingOnly ? 1 : 0)) : indexPath.row == 0;
    cell.textLabel.text = indexPath.section == 0 ? (indexPath.row == 0 ? @"From anyone" : @"People you follow") : (indexPath.row == 0 ? @"Anywhere" : @"Near you");
    UIImageView *radio = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"]];
    radio.frame = CGRectMake(0, 0, 22, 22); radio.tintColor = selected ? NFBColorAccent() : NFBColorSecondaryText(); cell.accessoryView = radio;
    cell.accessibilityTraits |= selected ? UIAccessibilityTraitSelected : 0;
    if (indexPath.section == 1 && indexPath.row == 1) {
      cell.textLabel.textColor = NFBColorSecondaryText(); cell.detailTextLabel.text = @"Location search isn’t available on Bluesky.";
      cell.selectionStyle = UITableViewCellSelectionStyleNone; cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    }
    if (indexPath.section == 0 && indexPath.row == 1 && ![[NFBAtprotoSession sharedSession] hasSession]) {
      cell.detailTextLabel.text = @"Sign in to filter by people you follow.";
      cell.accessibilityTraits |= UIAccessibilityTraitNotEnabled;
    }
  }
  return cell;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return self.settings || (indexPath.section == 1 && indexPath.row == 1) ? 72 : 52; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  if (self.settings || indexPath.section != 0) return;
  if (indexPath.row == 1 && ![[NFBAtprotoSession sharedSession] hasSession]) return;
  self.followingOnly = indexPath.row == 1;
  self.navigationItem.rightBarButtonItem.enabled = self.followingOnly != self.originalFollowingOnly;
  [tableView reloadData];
}
- (void)settingChanged:(UISwitch *)toggle {
  if (self.accountGeneration != [NFBAtprotoSession sharedSession].accountGeneration) { [self cancel]; return; }
  [NSUserDefaults.standardUserDefaults setBool:toggle.on forKey:NFBSearchDefaultsKey(toggle.tag == 0 ? @"hideSensitive" : @"excludeMuted")];
  if (self.settingsChanged) self.settingsChanged();
}
@end
