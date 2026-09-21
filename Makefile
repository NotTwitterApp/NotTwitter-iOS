ARCHS = arm64
TARGET := iphone:clang:16.5:14.0
PACKAGE_FORMAT = ipa
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = NotTwitterAtproto

NotTwitterAtproto_FILES = main.m NFBMediaLibraryViewController.m NFBMediaAudioSession.m NFBThreadModel.m NFBArticleReaderView.m NFBInteractiveSheet.m NFBAppDelegate.m NFBMainTabBarController.m NFBTimelineViewController.m NFBPostActionCoordinator.m NFBPostCell.m NFBMediaPreviewView.m NFBExternalCardView.m NFBMediaViewerViewController.m NFBQuotedPostView.m NFBComposeViewController.m NFBUndoTweetView.m NFBGIFService.m NFBMessagesViewController.m NFBAtprotoClient.m NFBAtprotoSession.m NFBBlueskyLoginViewController.m NFBAccountSwitcherViewController.m NFBNotificationCoordinator.m NFBLocalPostStore.m NFBModeration.m NFBTheme.m NFBLinkRouter.m NFBNeoFreeBirdUI.m NFBSideMenuViewController.m NFBSettingsViewController.m NFBDisplaySettingsViewController.m NFBTweetDetailViewController.m NFBSearchTypeaheadViewController.m NFBActorListViewController.m
NotTwitterAtproto_FILES += NFBPostLinkResolver.m NFBAccountAvatar.m NFBSearchOptions.m NFBAdvancedSearchViewController.m NFBSearchPagingScrollView.m
NotTwitterAtproto_FRAMEWORKS = UIKit Foundation SafariServices Security CoreText QuartzCore ImageIO AVFoundation AVKit UserNotifications AudioToolbox Photos PhotosUI WebKit
NotTwitterAtproto_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-nullability-completeness
NotTwitterAtproto_CODESIGN_FLAGS = -Sentitlements.plist
NotTwitterAtproto_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk
