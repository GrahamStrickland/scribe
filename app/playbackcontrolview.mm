#import "playbackcontrolview.h"

#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "audiomanager.h"
#import "logutil.h"
#import "playbackengine.h"
#import "time_format.h"

@interface PlaybackControlView () <PlaybackEngineDelegate>
@end

@implementation PlaybackControlView {
  PlaybackEngine *_engine;
  AudioManager _audioManager;

  NSSlider *_seekSlider;
  NSTextField *_currentTimeLabel;
  NSTextField *_remainingTimeLabel;

  NSButton *_openButton;
  NSButton *_recordButton;
  NSButton *_back10Button;
  NSButton *_playPauseButton;
  NSButton *_forward10Button;
  NSButton *_muteButton;
  NSSlider *_volumeSlider;

  NSImage *_playImage;
  NSImage *_pauseImage;
  NSImage *_volumeImage;
  NSImage *_mutedImage;
  NSImage *_recordImage;
  NSImage *_recordingImage;

  BOOL _recording;
}

- (instancetype)initWithEngine:(PlaybackEngine *)engine {
  if ((self = [super initWithFrame:NSZeroRect])) {
    _engine = engine;
    _engine.delegate = self;

    _playImage = [self symbol:@"play.circle.fill" label:@"Play"];
    _pauseImage = [self symbol:@"pause.circle.fill" label:@"Pause"];
    _volumeImage = [self symbol:@"speaker.wave.2.fill" label:@"Mute"];
    _mutedImage = [self symbol:@"speaker.slash.fill" label:@"Unmute"];
    _recordImage = [self symbol:@"record.circle" label:@"Record"];
    _recordingImage = [self symbol:@"stop.circle.fill" label:@"Stop Recording"];

    _recording = NO;

    [self buildSubviews];
    [self refresh];
  }
  return self;
}

#pragma mark - View construction

// Every transport button renders a fixed-size symbol inside an identically
// sized box so the row stays uniform and toggling play/pause or mute (whose
// symbols have different intrinsic widths) never shifts the layout.
static const CGFloat kSymbolPointSize = 16.0;
static const CGFloat kButtonSize = 30.0;

- (NSImage *)symbol:(NSString *)name label:(NSString *)label {
  NSImage *image = [NSImage imageWithSystemSymbolName:name
                             accessibilityDescription:label];
  NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration
      configurationWithPointSize:kSymbolPointSize
                          weight:NSFontWeightRegular];
  return [image imageWithSymbolConfiguration:config] ?: image;
}

- (NSButton *)buttonWithSymbol:(NSString *)name
                         label:(NSString *)label
                        action:(SEL)action {
  NSButton *button = [NSButton buttonWithImage:[self symbol:name label:label]
                                        target:self
                                        action:action];
  button.bezelStyle = NSBezelStyleRegularSquare;
  button.imageScaling = NSImageScaleProportionallyDown;
  button.toolTip = label;
  button.translatesAutoresizingMaskIntoConstraints = NO;
  [NSLayoutConstraint activateConstraints:@[
    [button.widthAnchor constraintEqualToConstant:kButtonSize],
    [button.heightAnchor constraintEqualToConstant:kButtonSize],
  ]];
  return button;
}

- (NSTextField *)timeLabelAlignedRight:(BOOL)right {
  NSTextField *label = [NSTextField labelWithString:@"0:00.000"];
  label.font = [NSFont monospacedDigitSystemFontOfSize:11
                                                weight:NSFontWeightRegular];
  label.alignment = right ? NSTextAlignmentRight : NSTextAlignmentLeft;
  label.textColor = NSColor.secondaryLabelColor;
  [label.widthAnchor constraintGreaterThanOrEqualToConstant:54].active = YES;
  return label;
}

- (void)buildSubviews {
  // Seek row: current time, scrub slider, remaining time.
  _currentTimeLabel = [self timeLabelAlignedRight:NO];
  _remainingTimeLabel = [self timeLabelAlignedRight:YES];

  _seekSlider = [NSSlider sliderWithValue:0.0
                                 minValue:0.0
                                 maxValue:1.0
                                   target:self
                                   action:@selector(seekChanged:)];
  _seekSlider.continuous = YES;

  NSStackView *seekRow = [NSStackView stackViewWithViews:@[
    _currentTimeLabel, _seekSlider, _remainingTimeLabel
  ]];
  seekRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  seekRow.spacing = 16;
  seekRow.alignment = NSLayoutAttributeCenterY;
  [_seekSlider
      setContentHuggingPriority:NSLayoutPriorityDefaultLow
                 forOrientation:NSLayoutConstraintOrientationHorizontal];

  // Transport row with leading (file/record), centered playback, and trailing
  // (volume) gravities.
  _openButton = [self buttonWithSymbol:@"folder"
                                 label:@"Open"
                                action:@selector(openDocument:)];
  _recordButton = [self buttonWithSymbol:@"record.circle"
                                   label:@"Record"
                                  action:@selector(recordTapped:)];

  _back10Button = [self buttonWithSymbol:@"gobackward.10"
                                   label:@"Back 10s"
                                  action:@selector(skipBackTapped:)];
  _playPauseButton = [self buttonWithSymbol:@"play.circle.fill"
                                      label:@"Play/Pause"
                                     action:@selector(playPauseTapped:)];
  _forward10Button = [self buttonWithSymbol:@"goforward.10"
                                      label:@"Forward 10s"
                                     action:@selector(skipForwardTapped:)];

  _muteButton = [self buttonWithSymbol:@"speaker.wave.2.fill"
                                 label:@"Mute"
                                action:@selector(muteTapped:)];

  _volumeSlider = [NSSlider sliderWithValue:1.0
                                   minValue:0.0
                                   maxValue:1.0
                                     target:self
                                     action:@selector(volumeChanged:)];
  _volumeSlider.continuous = YES;
  [_volumeSlider.widthAnchor constraintEqualToConstant:120].active = YES;

  NSStackView *transportRow = [[NSStackView alloc] init];
  transportRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
  transportRow.spacing = 12;
  transportRow.alignment = NSLayoutAttributeCenterY;
  [transportRow addView:_openButton inGravity:NSStackViewGravityLeading];
  [transportRow addView:_recordButton inGravity:NSStackViewGravityLeading];
  [transportRow addView:_back10Button inGravity:NSStackViewGravityCenter];
  [transportRow addView:_playPauseButton inGravity:NSStackViewGravityCenter];
  [transportRow addView:_forward10Button inGravity:NSStackViewGravityCenter];
  [transportRow addView:_muteButton inGravity:NSStackViewGravityTrailing];
  [transportRow addView:_volumeSlider inGravity:NSStackViewGravityTrailing];

  NSStackView *column =
      [NSStackView stackViewWithViews:@[ seekRow, transportRow ]];
  column.orientation = NSUserInterfaceLayoutOrientationVertical;
  column.spacing = 16;
  column.edgeInsets = NSEdgeInsetsMake(20, 32, 28, 32);
  column.translatesAutoresizingMaskIntoConstraints = NO;

  [self addSubview:column];
  [NSLayoutConstraint activateConstraints:@[
    [column.topAnchor constraintEqualToAnchor:self.topAnchor],
    [column.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    [column.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
    [column.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
  ]];
}

#pragma mark - Actions

- (void)openDocument:(id)sender {
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  panel.allowsMultipleSelection = NO;
  panel.canChooseDirectories = NO;
  panel.allowedContentTypes = @[ UTTypeAudio ];
  panel.message = @"Please choose an audio file";

  [panel beginSheetModalForWindow:self.window
                completionHandler:^(NSModalResponse response) {
                  if (response != NSModalResponseOK) {
                    return;
                  }
                  NSError *error = nil;
                  if (![self->_engine openURL:panel.URL error:&error]) {
                    [self presentPlaybackError:error];
                  }
                }];
}

- (void)playPauseTapped:(id)sender {
  [_engine togglePlayPause];
}

- (void)skipBackTapped:(id)sender {
  [_engine skipBy:-10.0];
}

- (void)skipForwardTapped:(id)sender {
  [_engine skipBy:10.0];
}

- (void)seekChanged:(NSSlider *)sender {
  [_engine seekToPosition:sender.doubleValue * _engine.duration];
}

- (void)volumeChanged:(NSSlider *)sender {
  _engine.volume = sender.floatValue;
}

- (void)muteTapped:(id)sender {
  _engine.muted = !_engine.muted;
  [self refresh];
}

- (void)recordTapped:(id)sender {
  if (!_recording) {
    AudioManager::PermissionStatus status = _audioManager.getPermission();
    if (status == AudioManager::Authorized) {
      [self startRecording];
      return;
    }
    if (status == AudioManager::Denied || status == AudioManager::Restricted) {
      [self presentPermissionDenied];
      return;
    }

    // NotDetermined: returns immediately; result arrives on the main thread.
    PlaybackControlView *blockSelf = self;
    _audioManager.requestPermission(
        [blockSelf](AudioManager::PermissionStatus result) {
          if (result == AudioManager::Authorized) {
            [blockSelf startRecording];
          } else {
            [blockSelf presentPermissionDenied];
          }
        });
  } else {
    [self stopRecording];
    return;
  }
}

- (void)saveDocument {
  NSSavePanel *panel = [NSSavePanel savePanel];
  UTType *wavType = [UTType typeWithIdentifier:@"com.microsoft.waveform-audio"];
  if (wavType) {
    panel.allowedContentTypes = @[ wavType ];
  }
  panel.message = @"Please choose a location to save captured audio file";

  [panel setCanCreateDirectories:YES];
  [panel setExtensionHidden:NO];

  [panel beginSheetModalForWindow:self.window
                completionHandler:^(NSModalResponse response) {
                  if (response != NSModalResponseOK) {
                    return;
                  }
                  NSError *error = nil;

                  std::string errorMessage;
                  NSURL *url = panel.URL;
                  NSString *path = [url path];
                  bool success = _audioManager.writeCapturedAudio(
                      std::string([path UTF8String]), errorMessage);
                  if (!success) {
                    NSString *errorMsg =
                        [NSString stringWithUTF8String:errorMessage.c_str()];
                    NSDictionary *userInfo =
                        @{NSLocalizedDescriptionKey : errorMsg};

                    error = [NSError errorWithDomain:@"playback-control-view"
                                                code:0
                                            userInfo:userInfo];
                    [self presentPlaybackError:error];
                  }
                }];
}

- (void)startRecording {
  if (_audioManager.startCapture()) {
    scribe_log("PlaybackControlView",
               "Audio capture authorized - starting recording");
    _recording = YES;

    [_engine clearMedia];
  }
  [self refresh];
}

- (void)stopRecording {
  if (_audioManager.stopCapture()) {
    scribe_log("PlaybackControlView", "Stopping recording");
    _recording = NO;

    [self saveDocument];
  }
  [self refresh];
}

#pragma mark - Alerts

- (void)presentPlaybackError:(NSError *)error {
  NSAlert *alert = [NSAlert alertWithError:error];
  [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (void)presentPermissionDenied {
  NSAlert *alert = [[NSAlert alloc] init];
  alert.messageText = @"System audio access is required to record";
  alert.informativeText =
      @"Grant Scribe access to record system audio in System "
      @"Settings ▸ Privacy & Security.";
  [alert addButtonWithTitle:@"OK"];
  [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

#pragma mark - PlaybackEngineDelegate

- (void)playbackEngineDidUpdate:(PlaybackEngine *)engine {
  [self refresh];
}

- (void)refresh {
  const BOOL hasMedia = _engine.hasMedia;
  const NSTimeInterval position = _engine.position;
  const NSTimeInterval duration = _engine.duration;

  _playPauseButton.image = _engine.isPlaying ? _pauseImage : _playImage;
  _muteButton.image = _engine.muted ? _mutedImage : _volumeImage;
  _recordButton.image = _recording ? _recordingImage : _recordImage;
  _recordButton.toolTip = _recording ? @"Stop Recording" : @"Record";

  const BOOL playbackEnabled = hasMedia && !_recording;
  _seekSlider.enabled = playbackEnabled;
  _back10Button.enabled = playbackEnabled;
  _playPauseButton.enabled = playbackEnabled;
  _forward10Button.enabled = playbackEnabled;

  _openButton.enabled = !_recording;
  _muteButton.enabled = !_recording;
  _volumeSlider.enabled = !_recording;

  if (duration > 0.0) {
    _seekSlider.doubleValue = position / duration;
  } else {
    _seekSlider.doubleValue = 0.0;
  }

  _currentTimeLabel.stringValue =
      @(scribe::format_to_minutes((long long)(position * 1000.0)).c_str());
  _remainingTimeLabel.stringValue =
      @(scribe::format_to_minutes((long long)((duration - position) * 1000.0))
            .c_str());
}

@end
