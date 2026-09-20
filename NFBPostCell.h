#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NFBPostCell;

@protocol NFBPostCellDelegate <NSObject>
@optional
- (void)postCellDidTapReply:(NFBPostCell *)cell;
- (void)postCellDidTapRepost:(NFBPostCell *)cell;
- (void)postCellDidTapLike:(NFBPostCell *)cell;
- (void)postCellDidTapBookmark:(NFBPostCell *)cell;
- (void)postCellDidTapShare:(NFBPostCell *)cell;
- (void)postCellDidTapMore:(NFBPostCell *)cell;
- (void)postCellDidLongPress:(NFBPostCell *)cell;
- (void)postCellDidTapAuthor:(NFBPostCell *)cell;
- (void)postCell:(NFBPostCell *)cell didTapLinkURL:(NSURL *)url;
- (void)postCell:(NFBPostCell *)cell didTapMediaAtIndex:(NSUInteger)index;
- (void)postCellDidTapExternalCard:(NFBPostCell *)cell;
- (void)postCellDidTapExternalCardWebsite:(NFBPostCell *)cell;
- (void)postCellDidTapQuotedPost:(NFBPostCell *)cell;
- (void)postCell:(NFBPostCell *)cell didTapQuotedMediaAtIndex:(NSUInteger)index;
- (void)postCellDidTapQuotedExternalCard:(NFBPostCell *)cell;
- (void)postCellDidTapQuotedExternalCardWebsite:(NFBPostCell *)cell;
@end

@interface NFBPostCell : UITableViewCell

@property (nonatomic, weak, nullable) id<NFBPostCellDelegate> delegate;
@property (nonatomic, strong, readonly, nullable) NSDictionary *feedItem;

- (void)configureWithFeedItem:(NSDictionary *)item;
- (void)setThreadConnectorAbove:(BOOL)above below:(BOOL)below;
- (void)setThreadConnectorAbove:(BOOL)above below:(BOOL)below compactSeparator:(BOOL)compactSeparator;
- (void)setMoreMenu:(nullable UIMenu *)menu API_AVAILABLE(ios(13.0));

@end

NS_ASSUME_NONNULL_END
