#import "NFBMediaLibraryViewController.h"
#import "NFBTheme.h"
#import <PhotosUI/PhotosUI.h>
#import "NFBMediaAttachmentPolicy.h"

@interface NFBMediaLibraryCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *image;
@property (nonatomic, strong) UILabel *selectionBadge;
@property (nonatomic, strong) UILabel *duration;
@property (nonatomic, copy) NSString *assetID;
@end
@implementation NFBMediaLibraryCell
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    _image = [[UIImageView alloc] init]; _image.contentMode = UIViewContentModeScaleAspectFill; _image.clipsToBounds = YES;
    _selectionBadge = [[UILabel alloc] init]; _selectionBadge.textAlignment = NSTextAlignmentCenter;
    _selectionBadge.font = NFBFont(14, NFBFontWeightBold); _selectionBadge.textColor = UIColor.whiteColor;
    _selectionBadge.layer.cornerRadius = 12; _selectionBadge.clipsToBounds = YES;
    _selectionBadge.layer.borderWidth = 2; _selectionBadge.layer.borderColor = UIColor.whiteColor.CGColor;
    _duration = [[UILabel alloc] init]; _duration.font = NFBFont(12, NFBFontWeightBold); _duration.textColor = UIColor.whiteColor;
    _duration.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:.5]; _duration.textAlignment = NSTextAlignmentRight;
    [self.contentView addSubview:_image]; [self.contentView addSubview:_selectionBadge]; [self.contentView addSubview:_duration];
  } return self;
}
- (void)layoutSubviews {
  [super layoutSubviews]; self.image.frame = self.contentView.bounds;
  self.selectionBadge.frame = CGRectMake(self.bounds.size.width - 31, 7, 24, 24);
  CGSize size = [self.duration sizeThatFits:self.bounds.size];
  self.duration.frame = CGRectMake(MAX(0, self.bounds.size.width - size.width - 10), self.bounds.size.height - 24, size.width + 6, 20);
}
@end

@interface NFBMediaLibraryViewController () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPhotoLibraryChangeObserver>
@property (nonatomic, strong) UICollectionView *collection;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *assets;
@property (nonatomic, strong) PHAssetCollection *album;
@property (nonatomic, strong) NSMutableArray<PHAsset *> *selection;
@property (nonatomic, strong) PHCachingImageManager *imageManager;
@property (nonatomic, strong) UIButton *albumButton;
@property (nonatomic, strong) UILabel *emptyLabel;
@property (nonatomic, assign) CGFloat layoutWidth;
@end
@implementation NFBMediaLibraryViewController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = NFBColorBackground();
  self.selection = [NSMutableArray array]; self.imageManager = [PHCachingImageManager new];
  self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add" style:UIBarButtonItemStyleDone target:self action:@selector(add)];
  self.navigationItem.rightBarButtonItem.enabled = NO;
  self.albumButton = [UIButton buttonWithType:UIButtonTypeCustom];
  self.albumButton.titleLabel.font = NFBFont(17, NFBFontWeightHeavy);
  [self.albumButton setTitleColor:NFBColorText() forState:UIControlStateNormal];
  [self.albumButton setTitle:@"All photos ▾" forState:UIControlStateNormal];
  [self.albumButton addTarget:self action:@selector(chooseAlbum) forControlEvents:UIControlEventTouchUpInside];
  [self.albumButton sizeToFit]; self.navigationItem.titleView = self.albumButton;
  UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new];
  layout.minimumInteritemSpacing = 1; layout.minimumLineSpacing = 1;
  self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
  self.collection.translatesAutoresizingMaskIntoConstraints = NO; self.collection.backgroundColor = NFBColorBackground();
  self.collection.dataSource = self; self.collection.delegate = self;
  [self.collection registerClass:NFBMediaLibraryCell.class forCellWithReuseIdentifier:@"media"];
  [self.view addSubview:self.collection];
  [NSLayoutConstraint activateConstraints:@[
    [self.collection.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:3],
    [self.collection.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
    [self.collection.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    [self.collection.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
  self.emptyLabel = [UILabel new]; self.emptyLabel.numberOfLines = 0; self.emptyLabel.textAlignment = NSTextAlignmentCenter;
  self.emptyLabel.font = NFBFont(16, NFBFontWeightRegular); self.emptyLabel.textColor = NFBColorSecondaryText();
  self.collection.backgroundView = self.emptyLabel;
  [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
  [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
    dispatch_async(dispatch_get_main_queue(), ^{ [self reloadAssets]; });
  }];
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; CGFloat width = self.collection.bounds.size.width; if (fabs(width - self.layoutWidth) > .5) { self.layoutWidth = width; [self.collection.collectionViewLayout invalidateLayout]; } }
- (void)photoLibraryDidChange:(PHChange *)change { dispatch_async(dispatch_get_main_queue(), ^{ [self reloadAssets]; }); }
- (void)reloadAssets {
  PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite];
  BOOL authorized = status == PHAuthorizationStatusAuthorized || status == PHAuthorizationStatusLimited;
  PHFetchOptions *options = [PHFetchOptions new];
  options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
  options.predicate = [NSPredicate predicateWithFormat:self.allowsVideo ? @"mediaType == 1 OR mediaType == 2" : @"mediaType == 1"];
  self.assets = authorized ? (self.album ? [PHAsset fetchAssetsInAssetCollection:self.album options:options] : [PHAsset fetchAssetsWithOptions:options]) : nil;
  self.emptyLabel.text = authorized ? (self.assets.count ? @"" : @"No photos or videos in this album.") : @"Allow photo access in Settings to choose photos and videos.";
  [self.collection reloadData];
}
- (void)chooseAlbum {
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Albums" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  [sheet addAction:[UIAlertAction actionWithTitle:@"All photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self selectAlbum:nil title:@"All photos"]; }]];
  for (NSNumber *type in @[@(PHAssetCollectionTypeSmartAlbum), @(PHAssetCollectionTypeAlbum)]) {
    PHFetchResult *albums = [PHAssetCollection fetchAssetCollectionsWithType:type.integerValue subtype:PHAssetCollectionSubtypeAny options:nil];
    for (PHAssetCollection *album in albums) {
      if (album.assetCollectionSubtype == PHAssetCollectionSubtypeSmartAlbumAllHidden) continue;
      [sheet addAction:[UIAlertAction actionWithTitle:album.localizedTitle ?: @"Album" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self selectAlbum:album title:album.localizedTitle]; }]];
    }
  }
  if ([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite] == PHAuthorizationStatusLimited) {
    [sheet addAction:[UIAlertAction actionWithTitle:@"Choose more photos" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [[PHPhotoLibrary sharedPhotoLibrary] presentLimitedLibraryPickerFromViewController:self]; }]];
  }
  [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = self.albumButton; sheet.popoverPresentationController.sourceRect = self.albumButton.bounds;
  [self presentViewController:sheet animated:YES completion:nil];
}
- (void)selectAlbum:(PHAssetCollection *)album title:(NSString *)title {
  self.album = album; [self.albumButton setTitle:[title stringByAppendingString:@" ▾"] forState:UIControlStateNormal];
  [self.albumButton sizeToFit]; [self reloadAssets];
}
- (NSInteger)collectionView:(UICollectionView *)collection numberOfItemsInSection:(NSInteger)section { return self.assets.count + 1; }
- (CGSize)collectionView:(UICollectionView *)collection layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)path {
  NSUInteger columns = self.view.bounds.size.width > self.view.bounds.size.height ? 5 : 3;
  CGFloat side = floor((collection.bounds.size.width - (columns - 1)) / columns); return CGSizeMake(side, side);
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collection cellForItemAtIndexPath:(NSIndexPath *)path {
  NFBMediaLibraryCell *cell = [collection dequeueReusableCellWithReuseIdentifier:@"media" forIndexPath:path];
  cell.image.image = nil; cell.duration.hidden = YES; cell.selectionBadge.hidden = path.item == 0;
  cell.image.contentMode = path.item == 0 ? UIViewContentModeCenter : UIViewContentModeScaleAspectFill;
  cell.backgroundColor = NFBColorElevatedBackground(); cell.image.tintColor = NFBColorText();
  cell.assetID = nil; cell.contentView.alpha = 1;
  if (!path.item) { cell.image.image = NFBTemplateIcon(@"nfb_camera"); cell.accessibilityLabel = @"Camera"; return cell; }
  PHAsset *asset = self.assets[path.item - 1]; cell.assetID = asset.localIdentifier;
  NSUInteger selected = [self.selection indexOfObjectPassingTest:^BOOL(PHAsset *a, NSUInteger i, BOOL *stop) { return [a.localIdentifier isEqualToString:asset.localIdentifier]; }];
  cell.selectionBadge.text = selected == NSNotFound ? @"" : [NSString stringWithFormat:@"%lu", (unsigned long)selected + 1];
  cell.selectionBadge.backgroundColor = selected == NSNotFound ? [UIColor.blackColor colorWithAlphaComponent:.35] : NFBColorAccent();
  BOOL video = asset.mediaType == PHAssetMediaTypeVideo;
  BOOL selectedVideo = self.selection.firstObject.mediaType == PHAssetMediaTypeVideo;
  BOOL unavailable = self.selection.count && (video || selectedVideo) && selected == NSNotFound;
  if (unavailable || (selected == NSNotFound && self.selection.count >= self.photoLimit)) cell.contentView.alpha = .35;
  cell.duration.hidden = !video;
  cell.duration.text = [NSString stringWithFormat:@"%lu:%02lu", (unsigned long)asset.duration / 60, (unsigned long)asset.duration % 60];
  cell.accessibilityLabel = [NSString stringWithFormat:@"%@%@", video ? @"Video" : @"Photo", selected == NSNotFound ? @"" : [@", selected " stringByAppendingString:cell.selectionBadge.text]];
  cell.accessibilityTraits = UIAccessibilityTraitButton | (selected == NSNotFound ? 0 : UIAccessibilityTraitSelected);
  NSString *assetID = asset.localIdentifier;
  PHImageRequestOptions *options = [PHImageRequestOptions new]; options.networkAccessAllowed = YES;
  CGFloat size = MAX(120, self.view.bounds.size.width / 3) * UIScreen.mainScreen.scale;
  [self.imageManager requestImageForAsset:asset targetSize:CGSizeMake(size, size) contentMode:PHImageContentModeAspectFill options:options resultHandler:^(UIImage *image, NSDictionary *info) {
    dispatch_async(dispatch_get_main_queue(), ^{ if ([cell.assetID isEqualToString:assetID] && image) cell.image.image = image; });
  }];
  return cell;
}
- (void)collectionView:(UICollectionView *)collection didSelectItemAtIndexPath:(NSIndexPath *)path {
  if (!path.item) { [self openCamera]; return; }
  PHAsset *asset = self.assets[path.item - 1];
  NSUInteger selected = [self.selection indexOfObjectPassingTest:^BOOL(PHAsset *a, NSUInteger i, BOOL *stop) { return [a.localIdentifier isEqualToString:asset.localIdentifier]; }];
  if (selected != NSNotFound) [self.selection removeObjectAtIndex:selected];
  else {
    if (self.selection.count >= self.photoLimit || (self.selection.count && (asset.mediaType == PHAssetMediaTypeVideo || self.selection.firstObject.mediaType == PHAssetMediaTypeVideo))) return;
    [self.selection addObject:asset];
  }
  self.navigationItem.rightBarButtonItem.enabled = self.selection.count > 0;
  self.navigationItem.rightBarButtonItem.title = self.selection.count ? [NSString stringWithFormat:@"Add (%lu)", (unsigned long)self.selection.count] : @"Add";
  [self.collection reloadData];
}
- (void)openCamera {
  if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) return;
  UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
  for (NSNumber *video in self.allowsVideo ? @[@NO, @YES] : @[@NO]) {
    [sheet addAction:[UIAlertAction actionWithTitle:video.boolValue ? @"Record video" : @"Take photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
      [self dismissViewControllerAnimated:YES completion:^{ if (self.cameraHandler) self.cameraHandler(video.boolValue); }];
    }]];
  }
  [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  sheet.popoverPresentationController.sourceView = self.collection; sheet.popoverPresentationController.sourceRect = CGRectMake(0, 0, 120, 120);
  [self presentViewController:sheet animated:YES completion:nil];
}
- (void)add { NSArray *selection = [self.selection copy]; [self dismissViewControllerAnimated:YES completion:^{ if (self.selectionHandler) self.selectionHandler(selection); }]; }
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)dealloc { [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self]; [self.imageManager stopCachingImagesForAllAssets]; }
@end
