#import "NFBUndoTweetView.h"
#import "NFBTheme.h"
#import <QuartzCore/QuartzCore.h>

@interface NFBUndoTweetView ()
@property (nonatomic, strong, readwrite) UIButton *undoButton;
@property (nonatomic, strong, readwrite) UIButton *sendNowButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) CAShapeLayer *progressTrackLayer;
@property (nonatomic, strong) CAShapeLayer *progressLayer;
@end

@implementation NFBUndoTweetView

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (!self) return nil;

  // Twitter 9.67 T1UndoSendInfoView uses a 16pt ring with a 4pt round
  // stroke, a bold sending label, and text buttons rather than its demo SVG.
  self.statusLabel = [[UILabel alloc] init];
  self.statusLabel.text = @"Sending Tweet…";
  self.statusLabel.numberOfLines = 0;
  self.statusLabel.accessibilityLabel = @"Pending Tweet";
  [self addSubview:self.statusLabel];

  self.progressTrackLayer = [CAShapeLayer layer];
  self.progressLayer = [CAShapeLayer layer];
  for (CAShapeLayer *layer in @[self.progressTrackLayer, self.progressLayer]) {
    layer.fillColor = UIColor.clearColor.CGColor;
    layer.lineWidth = 4.0;
    layer.lineCap = kCALineCapRound;
    [self.layer addSublayer:layer];
  }
  self.progressLayer.strokeEnd = 0.0;

  self.undoButton = [NFBPillButton buttonWithType:UIButtonTypeSystem];
  [self.undoButton setTitle:@"Undo" forState:UIControlStateNormal];
  self.undoButton.accessibilityHint = @"Return to editing before this Tweet is sent.";
  [self addSubview:self.undoButton];

  self.sendNowButton = [NFBPillButton buttonWithType:UIButtonTypeSystem];
  [self.sendNowButton setTitle:@"Send now" forState:UIControlStateNormal];
  [self addSubview:self.sendNowButton];

  // Keep the real controls individually reachable by VoiceOver.
  self.isAccessibilityElement = NO;
  self.accessibilityElements = @[self.statusLabel, self.sendNowButton, self.undoButton];
  [self applyTheme];
  return self;
}

- (void)applyTheme {
  self.backgroundColor = NFBColorBackground();
  self.statusLabel.font = NFBFont(15.0, NFBFontWeightBold);
  self.statusLabel.textColor = NFBColorText();
  self.progressTrackLayer.strokeColor = NFBColorBorder().CGColor;
  self.progressLayer.strokeColor = NFBColorAccent().CGColor;
  NFBIPAApplyButtonAppearance(self.undoButton, NFBIPAButtonStylePrimary, NFBIPAButtonSizeSmall);
  NFBIPAApplyButtonAppearance(self.sendNowButton, NFBIPAButtonStyleText, NFBIPAButtonSizeMedium);
  // TFNButton size classes 2 (Undo) and 3 (Send now) use 8/16pt insets.
  [self invalidateIntrinsicContentSize];
  [self setNeedsLayout];
}

- (CGSize)sizeThatFits:(CGSize)size {
  CGSize undoSize = [self.undoButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
  CGSize sendSize = [self.sendNowButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
  CGFloat labelWidth = MAX(1.0, size.width - 32.0);
  CGFloat statusHeight = MAX(20.0, ceil([self.statusLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)].height));
  CGFloat buttonHeight = MAX(undoSize.height, sendSize.height);
  return CGSizeMake(size.width, 4.0 + statusHeight + 12.0 + buttonHeight + 4.0);
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat width = CGRectGetWidth(self.bounds);
  CGSize undoSize = [self.undoButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
  CGSize sendSize = [self.sendNowButton sizeThatFits:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)];
  CGFloat labelWidth = MAX(1.0, width - 32.0);
  CGFloat statusHeight = MAX(20.0, ceil([self.statusLabel sizeThatFits:CGSizeMake(labelWidth, CGFLOAT_MAX)].height));
  BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
  self.statusLabel.frame = CGRectMake(rtl ? 0.0 : 32.0, 4.0, labelWidth, statusHeight);

  CGFloat buttonHeight = MAX(undoSize.height, sendSize.height);
  CGFloat buttonY = CGRectGetMaxY(self.statusLabel.frame) + 12.0;
  CGFloat undoX = rtl ? 0.0 : width - undoSize.width;
  CGFloat sendX = rtl ? undoSize.width + 4.0 : undoX - 4.0 - sendSize.width;
  self.undoButton.frame = CGRectMake(undoX, buttonY + (buttonHeight - undoSize.height) * 0.5, undoSize.width, undoSize.height);
  self.sendNowButton.frame = CGRectMake(sendX, buttonY + (buttonHeight - sendSize.height) * 0.5, sendSize.width, sendSize.height);

  UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:CGPointMake(8.0, 8.0)
                                                   radius:8.0
                                               startAngle:-M_PI_2
                                                 endAngle:M_PI * 1.5
                                                clockwise:YES];
  CGRect ringFrame = CGRectMake(rtl ? width - 20.0 : 4.0, 4.0 + (statusHeight - 16.0) * 0.5, 16.0, 16.0);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (CAShapeLayer *layer in @[self.progressTrackLayer, self.progressLayer]) {
    layer.frame = ringFrame;
    layer.path = ring.CGPath;
  }
  [CATransaction commit];
}

- (void)updateWithRemainingTime:(NSTimeInterval)remaining totalInterval:(NSTimeInterval)totalInterval {
  CGFloat elapsed = totalInterval > 0.0 ? 1.0 - MAX(0.0, MIN(1.0, remaining / totalInterval)) : 1.0;
  CAShapeLayer *presentation = (CAShapeLayer *)self.progressLayer.presentationLayer;
  CGFloat previous = presentation ? presentation.strokeEnd : self.progressLayer.strokeEnd;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.progressLayer.strokeEnd = elapsed;
  [CATransaction commit];
  if (elapsed > previous && !UIAccessibilityIsReduceMotionEnabled()) {
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    animation.fromValue = @(previous);
    animation.toValue = @(elapsed);
    animation.duration = MIN(0.25, MAX(0.0, remaining));
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [self.progressLayer addAnimation:animation forKey:@"undoProgress"];
  }
  self.statusLabel.accessibilityValue = [NSString stringWithFormat:@"%ld seconds remaining", (long)ceil(MAX(0.0, remaining))];
}

- (void)resetProgress {
  [self.progressLayer removeAllAnimations];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  self.progressLayer.strokeEnd = 0.0;
  [CATransaction commit];
}

@end
