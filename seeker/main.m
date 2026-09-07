#import <UIKit/UIKit.h>
#import "Detection.h"

@interface SeekerViewController : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *results;
@property(nonatomic, copy) NSArray<NSDictionary *> *visible;
@property(nonatomic, strong) UISegmentedControl *filter;
@property(nonatomic) BOOL scanning;
@end

@implementation SeekerViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Seeker";
    self.filter = [[UISegmentedControl alloc] initWithItems:@[@"Fired", @"All checks"]];
    self.filter.selectedSegmentIndex = 0;
    [self.filter addTarget:self action:@selector(updateResults) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = self.filter;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(scan)];
    self.navigationItem.rightBarButtonItem.accessibilityLabel = @"Run detections again";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 100;
    self.refreshControl = [UIRefreshControl new];
    [self.refreshControl addTarget:self action:@selector(scan) forControlEvents:UIControlEventValueChanged];
    [self scan];
}
- (void)scan {
    if (self.scanning) return;
    self.scanning = YES;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.navigationItem.prompt = @"Running detections…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSArray *results = SKRunChecks();
            dispatch_async(dispatch_get_main_queue(), ^{
                self.results = results;
                self.scanning = NO;
                self.navigationItem.rightBarButtonItem.enabled = YES;
                [self.refreshControl endRefreshing];
                [self updateResults];
            });
        }
    });
}
- (void)updateResults {
    NSMutableArray *fired = [NSMutableArray array];
    NSUInteger unavailable = 0;
    for (NSDictionary *row in self.results) {
        if ([row[@"state"] isEqual:@"FIRED"]) [fired addObject:row];
        if ([row[@"state"] isEqual:@"UNAVAILABLE"]) unavailable++;
    }
    self.visible = self.filter.selectedSegmentIndex == 0 ? fired : self.results;
    if (!self.scanning) self.navigationItem.prompt = [NSString stringWithFormat:@"%lu fired · %lu unavailable · %lu checks", (unsigned long)fired.count, (unsigned long)unavailable, (unsigned long)self.results.count];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.visible.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView; (void)section;
    if (self.scanning) return @"Seeker";
    return self.visible.count ? @"Seeker" : @"No detections fired. Check unavailable results in All checks.";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [NSString stringWithFormat:@"iOS %@ · Seeker 0.1.0\nResults describe this app's process. Its rootless installation and ad hoc signature can fire checks. Debuggers, JIT and open ports can have legitimate uses. NOT OBSERVED does not prove a stock device.", UIDevice.currentDevice.systemVersion];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Result"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Result"];
    NSDictionary *row = self.visible[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", row[@"state"], row[@"name"]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@", row[@"category"], row[@"evidence"]];
    cell.textLabel.numberOfLines = cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.textLabel.adjustsFontForContentSizeCategory = cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = [row[@"state"] isEqual:@"FIRED"] ? UIColor.systemRedColor : [row[@"state"] isEqual:@"UNAVAILABLE"] ? UIColor.systemOrangeColor : UIColor.labelColor;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
@end

@interface SeekerAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation SeekerAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[SeekerViewController alloc] initWithStyle:UITableViewStyleInsetGrouped]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(SeekerAppDelegate.class)); }
}
