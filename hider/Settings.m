#import <Preferences/PSViewController.h>
#import <objc/message.h>
#import "Config.h"

@interface HSSettingsController : PSViewController <UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating>
@property(nonatomic) UITableViewController *list;
@property(nonatomic) UISearchController *search;
@property(nonatomic) NSArray<NSDictionary *> *apps;
@property(nonatomic) NSArray<NSDictionary *> *visible;
@property(nonatomic) NSMutableSet<NSString *> *enabled;
@property(nonatomic) NSString *loadError;
@property(nonatomic) NSString *configurationError;
@end

@implementation HSSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Hider";
    self.list = [[UITableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self addChildViewController:self.list];
    self.list.view.frame = self.view.bounds;
    self.list.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.list.view];
    [self.list didMoveToParentViewController:self];
    self.list.tableView.dataSource = self;
    self.list.tableView.delegate = self;
    self.list.tableView.rowHeight = UITableViewAutomaticDimension;
    self.list.tableView.estimatedRowHeight = 64;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = @"App name or bundle ID";
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Disable all" style:UIBarButtonItemStylePlain target:self action:@selector(disableAll)];
    self.list.refreshControl = [UIRefreshControl new];
    [self.list.refreshControl addTarget:self action:@selector(reloadApps) forControlEvents:UIControlEventValueChanged];
    NSError *error = nil;
    self.enabled = [HSReadApps(&error) mutableCopy] ?: [NSMutableSet set];
    if (error && error.code != NSFileReadNoSuchFileError) self.configurationError = [@"Could not read saved selections: " stringByAppendingString:error.localizedDescription];
    [self reloadApps];
}
- (void)reloadApps {
    self.list.refreshControl.enabled = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableDictionary *byID = [NSMutableDictionary dictionary];
        NSString *failure = nil;
        @try {
            Class cls = NSClassFromString(@"LSApplicationWorkspace");
            SEL shared = NSSelectorFromString(@"defaultWorkspace");
            id workspace = [cls respondsToSelector:shared] ? ((id (*)(id, SEL))objc_msgSend)(cls, shared) : nil;
            void (^add)(id) = ^(id proxy) {
                SEL bundleID = NSSelectorFromString(@"bundleIdentifier"), name = NSSelectorFromString(@"localizedName");
                id identifier = [proxy respondsToSelector:bundleID] ? ((id (*)(id, SEL))objc_msgSend)(proxy, bundleID) : nil;
                id label = [proxy respondsToSelector:name] ? ((id (*)(id, SEL))objc_msgSend)(proxy, name) : nil;
                if (![identifier isKindOfClass:NSString.class] || ![identifier length]) return;
                if (![label isKindOfClass:NSString.class] || ![label length]) label = identifier;
                byID[identifier] = @{@"id": identifier, @"name": label};
            };
            SEL enumerate = NSSelectorFromString(@"enumerateApplicationsOfType:block:");
            if ([workspace respondsToSelector:enumerate]) {
                // LaunchServices types: 0 system, 1 user. Keep hidden apps too.
                for (NSUInteger type = 0; type < 2; ++type)
                    ((void (*)(id, SEL, NSUInteger, id))objc_msgSend)(workspace, enumerate, type, add);
            } else {
                SEL all = NSSelectorFromString(@"allInstalledApplications");
                id proxies = [workspace respondsToSelector:all] ? ((id (*)(id, SEL))objc_msgSend)(workspace, all) : nil;
                if ([proxies isKindOfClass:NSArray.class]) for (id proxy in proxies) add(proxy);
            }
            if (!byID.count) failure = @"LaunchServices returned no apps. Pull to retry. Check that PreferenceLoader supports this device.";
        } @catch (NSException *exception) {
            failure = [@"App list unavailable: " stringByAppendingString:exception.reason ?: exception.name];
        }
        NSArray *apps = [byID.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSComparisonResult order = [a[@"name"] localizedStandardCompare:b[@"name"]];
            return order == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : order;
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.apps = apps;
            self.loadError = failure ?: self.configurationError;
            [self updateSearchResultsForSearchController:self.search];
            self.list.refreshControl.enabled = YES;
            [self.list.refreshControl endRefreshing];
        });
    });
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query = controller.searchBar.text ?: @"";
    self.visible = !query.length ? self.apps : [self.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *app, NSDictionary *bindings) {
        (void)bindings;
        return [app[@"name"] localizedStandardContainsString:query] || [app[@"id"] localizedStandardContainsString:query];
    }]];
    [self.list.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.visible.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [NSString stringWithFormat:@"%lu apps · %lu selected", (unsigned long)self.apps.count, (unsigned long)self.enabled.count];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.loadError ?: @"Checked apps hide known jailbreak paths. Close and reopen an app after changing its selection. Settings and SpringBoard are protected. This does not hide loaded tweaks or other non-filesystem detections. Pull to refresh installed apps.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *app = self.visible[indexPath.row];
    BOOL protected = HSProtectedApp(app[@"id"]), selected = [self.enabled containsObject:app[@"id"]];
    cell.textLabel.text = app[@"name"];
    cell.detailTextLabel.text = protected ? [app[@"id"] stringByAppendingString:@" · Protected"] : app[@"id"];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.textLabel.adjustsFontForContentSizeCategory = cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.textColor = protected ? UIColor.secondaryLabelColor : UIColor.labelColor;
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.selectionStyle = protected ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleDefault;
    cell.accessibilityTraits = UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0) | (protected ? UIAccessibilityTraitNotEnabled : 0);
    cell.accessibilityValue = protected ? @"Protected, always disabled" : selected ? @"Hiding enabled" : @"Hiding disabled";
    return cell;
}
- (void)saveSelection:(NSMutableSet *)next {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:[next.allObjects sortedArrayUsingSelector:@selector(compare:)] format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (data && [data writeToFile:HSConfigPath options:NSDataWritingAtomic error:&error]) {
        self.enabled = next;
        self.loadError = nil;
        self.configurationError = nil;
        [self.list.tableView reloadData];
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Selection not saved" message:error.localizedDescription ?: @"Reinstall Hider to restore its data directory." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *identifier = self.visible[indexPath.row][@"id"];
    if (HSProtectedApp(identifier)) return;
    NSMutableSet *next = [self.enabled mutableCopy];
    if ([next containsObject:identifier]) [next removeObject:identifier]; else [next addObject:identifier];
    [self saveSelection:next];
}
- (void)disableAll { [self saveSelection:[NSMutableSet set]]; }
@end
