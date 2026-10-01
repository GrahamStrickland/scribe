#import "audiocapturemanager.h"
#import "logutil.h"
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>

#include <CoreAudio/AudioHardwareTapping.h>
#include <CoreAudio/CATapDescription.h>

// Constants for audio format
static const Float64 kTargetSampleRate = 22050.0;
static const UInt32 kTargetChannelCount = 1;
static const UInt32 kPreferredBufferSize =
    4096; // Added preferred buffer size (samples)

// Constants for device monitoring
static const UInt32 kDeviceChangeScope = kAudioObjectPropertyScopeGlobal;
static const UInt32 kDeviceChangeElement = kAudioObjectPropertyElementMain;

@interface AudioCaptureManager () {
}
@end

@implementation AudioCaptureManager

#pragma mark - Singleton

static AudioCaptureManager *sharedInstance = nil;

+ (instancetype)sharedInstance {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    scribe_log("AudioCaptureManager", "Creating singleton instance");
    sharedInstance = [[self alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    [self initializeTCCFramework];

    // Initialize audio properties
    _isCapturing = NO;
    _audioQueue = dispatch_queue_create("audio-capture-manager-queue",
                                        DISPATCH_QUEUE_SERIAL);
    _aggregateDeviceID = kAudioDeviceUnknown;
    _deviceProcID = NULL;

    if ([self checkTCCPermission:@"kTCCServiceAudioCapture"] == 0) {
      NSError *error = nil;
      if (![self setupAudioTapIfNeeded:&error]) {
        scribe_log("AudioCaptureManager",
                   std::string("Failed to setup audio tap: ") +
                       std::string([error.localizedDescription UTF8String]),
                   OS_LOG_TYPE_ERROR);
      }
      if (![self setupAggregateDeviceIfNeeded:&error]) {
        scribe_log("AudioCaptureManager",
                   std::string("Failed to setup aggregate device: ") +
                       std::string([error.localizedDescription UTF8String]),
                   OS_LOG_TYPE_ERROR);
      }
      [self startDeviceMonitoring];
    }
  }

  return self;
}

- (void)dealloc {
  scribe_log("AudioCaptureManager", "Deallocating");
  [self stopDeviceMonitoring];
  [self destroyAudioResources];

  [_audioFormatCallback release];
  _audioFormatCallback = nil;
  [_audioDataCallback release];
  _audioDataCallback = nil;

  if (_tccHandle) {
    scribe_log("AudioCaptureManager", "Closing TCC framework handle");
    dlclose(_tccHandle);
  }
  [super dealloc];
}

#pragma mark - Audio Control Methods

- (BOOL)startCapture:(NSError **)error {
  if (_isCapturing) {
    return YES;
  }

  scribe_log("AudioCaptureManager", "Starting audio capture");

  auto permission = [self getPermission];
  if (permission != PermissionStatus::PermissionStatusAuthorized) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"audio-capture-manager"
                     code:permission
                 userInfo:@{
                   NSLocalizedDescriptionKey :
                       @"Audio capture permission has not been granted",
                   @"ErrorLocation" : @"getPermission"
                 }];
    }
    return NO;
  }

  // Set up audio tap and aggregate device if needed
  if (![self setupAudioTapIfNeeded:error]) {
    return NO;
  }

  if (![self setupAggregateDeviceIfNeeded:error]) {
    return NO;
  }

  // Log device IDs for debugging
  scribe_log("AudioCaptureManager", "Using aggregate device ID: " +
                                        std::to_string(_aggregateDeviceID));
  scribe_log("AudioCaptureManager",
             "Tap object ID: " + std::to_string(_tapObjectID));

  // Set up IO proc for the aggregate device instead of tap
  OSStatus status =
      AudioDeviceCreateIOProcID(_aggregateDeviceID, HandleAudioDeviceIOProc,
                                (__bridge void *)self, &_deviceProcID);

  if (status != noErr) {
    if (error) {
      NSString *errorDescription = [NSString
          stringWithFormat:
              @"Failed to create IO proc for aggregate device. Status code: "
              @"%d. This typically means there was an issue setting up the "
              @"audio process callback for the device.",
              (int)status];

      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey : errorDescription,
                                 @"OSStatus" : @(status),
                                 @"ErrorLocation" : @"AudioDeviceCreateIOProcID"
                               }];
    }
    return NO;
  }

  // Start the IO proc on the aggregate device
  status = AudioDeviceStart(_aggregateDeviceID, _deviceProcID);
  if (status != noErr) {
    AudioDeviceDestroyIOProcID(_aggregateDeviceID, _deviceProcID);
    _deviceProcID = NULL;
    if (error) {
      *error = [NSError
          errorWithDomain:@"audio-capture-manager"
                     code:status
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to start audio capture"
                 }];
    }
    return NO;
  }

  // Captured data is downmixed and resampled before delivery (see
  // handleAudioInput:), so report the delivered format rather than the
  // aggregate device's native one. Queued on the main thread ahead of any
  // audio data, which is only delivered once _isCapturing is set. The callback
  // is captured instead of self so a pending block never keeps self alive.
  void (^formatCallback)(Float64, UInt32) = _audioFormatCallback;
  if (formatCallback) {
    dispatch_async(dispatch_get_main_queue(), ^{
      formatCallback(kTargetSampleRate, kTargetChannelCount);
    });
  }

  _isCapturing = YES;
  scribe_log("AudioCaptureManager", "Audio capture started successfully");
  return YES;
}

- (BOOL)stopCapture:(NSError **)error {
  if (!_isCapturing) {
    return YES;
  }

  scribe_log("AudioCaptureManager", "Stopping audio capture");

  // Stop and destroy the IO proc on the aggregate device
  if (_deviceProcID != NULL) {
    OSStatus status = AudioDeviceStop(_aggregateDeviceID, _deviceProcID);
    if (status != noErr) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"audio-capture-manager"
                       code:status
                   userInfo:@{
                     NSLocalizedDescriptionKey : @"Failed to stop audio capture"
                   }];
      }
      return NO;
    }

    status = AudioDeviceDestroyIOProcID(_aggregateDeviceID, _deviceProcID);
    if (status != noErr) {
      if (error) {
        *error = [NSError
            errorWithDomain:@"audio-capture-manager"
                       code:status
                   userInfo:@{
                     NSLocalizedDescriptionKey : @"Failed to destroy IO proc"
                   }];
      }
      return NO;
    }

    _deviceProcID = NULL;
  }

  _isCapturing = NO;
  scribe_log("AudioCaptureManager", "Audio capture stopped successfully");
  return YES;
}

#pragma mark - Audio Callbacks

- (void)setAudioFormatCallback:(void (^)(Float64 sampleRate,
                                         UInt32 numChannels))callback {
  void (^previousCallback)(Float64, UInt32) = _audioFormatCallback;
  _audioFormatCallback = [callback copy];
  [previousCallback release];
}

- (void)setAudioDataCallback:(void (^)(NSData *audioData))callback {
  void (^previousCallback)(NSData *) = _audioDataCallback;
  _audioDataCallback = [callback copy];
  [previousCallback release];
}

static OSStatus HandleAudioDeviceIOProc(AudioDeviceID inDevice,
                                        const AudioTimeStamp *inNow,
                                        const AudioBufferList *inInputData,
                                        const AudioTimeStamp *inInputTime,
                                        AudioBufferList *outOutputData,
                                        const AudioTimeStamp *inOutputTime,
                                        void *inClientData) {
  AudioCaptureManager *audioManager =
      (__bridge AudioCaptureManager *)inClientData;
  [audioManager handleAudioInput:inInputData];
  return noErr;
}

- (void)handleAudioInput:(const AudioBufferList *)bufferList {
  if (!_isCapturing || !_audioDataCallback) {
    return;
  }

  @autoreleasepool {
    // Validate input data
    if (!bufferList || bufferList->mNumberBuffers == 0) {
      scribe_log("AudioCaptureManager", "Invalid buffer list received",
                 OS_LOG_TYPE_ERROR);
      return;
    }

    const AudioBuffer *buffer = &bufferList->mBuffers[0];
    UInt32 numFrames = buffer->mDataByteSize / sizeof(Float32);

    // Determine channel count based on source format
    BOOL isInterleaved =
        !(_sourceFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved);
    UInt32 numChannels = _sourceFormat.mChannelsPerFrame;
    if (numChannels == 0) {
      numChannels = bufferList->mNumberBuffers;
    }

    // For interleaved data, adjust numFrames
    if (isInterleaved) {
      numFrames = numFrames / numChannels;
    }

    // Validate frame count
    if (numFrames == 0) {
      scribe_log("AudioCaptureManager", "Invalid frame count",
                 OS_LOG_TYPE_ERROR);
      return;
    }

    @try {
      // Convert to mono
      Float32 *monoBuffer = [self convertToMono:bufferList numFrames:numFrames];
      if (!monoBuffer) {
        return;
      }

      // Resample
      UInt32 resampledFrameLength = 0;
      Float32 *resampledBuffer = [self resampleBuffer:monoBuffer
                                          inputFrames:numFrames
                                         outputFrames:&resampledFrameLength];
      free(monoBuffer);

      if (!resampledBuffer) {
        return;
      }

      // Create NSData safely
      NSData *audioData =
          [[NSData alloc] initWithBytes:resampledBuffer
                                 length:resampledFrameLength * sizeof(Float32)];
      free(resampledBuffer);

      // Send to callback on main thread
      if (audioData) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (self->_audioDataCallback) {
            self->_audioDataCallback(audioData);
          }
        });
      }
    } @catch (NSException *exception) {
      scribe_log("AudioCaptureManager",
                 std::string("Exception in handleAudioInput: ") +
                     std::string([exception.description UTF8String]),
                 OS_LOG_TYPE_ERROR);
    }
  }
}

- (Float32 *)convertToMono:(const AudioBufferList *)bufferList
                 numFrames:(UInt32)numFrames {
  if (!bufferList || bufferList->mNumberBuffers == 0) {
    scribe_log("AudioCaptureManager", "Invalid buffer list received",
               OS_LOG_TYPE_ERROR);
    return NULL;
  }

  const AudioBuffer *buffer = &bufferList->mBuffers[0];
  if (!buffer->mData || buffer->mDataByteSize == 0) {
    scribe_log("AudioCaptureManager", "Invalid buffer data received",
               OS_LOG_TYPE_ERROR);
    return NULL;
  }

  Float32 *samples = (Float32 *)buffer->mData;

  // Determine channel count and format based on source format
  BOOL isInterleaved =
      !(_sourceFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved);
  UInt32 numChannels = _sourceFormat.mChannelsPerFrame;
  if (numChannels == 0) {
    numChannels = bufferList->mNumberBuffers;
  }

  // Allocate mono buffer
  Float32 *monoBuffer = (Float32 *)calloc(numFrames, sizeof(Float32));
  if (!monoBuffer) {
    scribe_log("AudioCaptureManager",
               "Failed to allocate memory for mono buffer", OS_LOG_TYPE_ERROR);
    return NULL;
  }

  // Merge channels to mono based on format
  if (isInterleaved) {
    // Handle interleave d format (all channels in one buffer)
    for (UInt32 frame = 0; frame < numFrames; frame++) {
      float sum = 0.0f;
      for (UInt32 channel = 0; channel < numChannels; channel++) {
        sum += samples[frame * numChannels + channel];
      }
      monoBuffer[frame] = sum / numChannels;
    }
  } else {
    // Handle non-interleaved format (separate buffers for each channel)
    for (UInt32 frame = 0; frame < numFrames; frame++) {
      float sum = 0.0f;
      for (UInt32 channel = 0; channel < numChannels; channel++) {
        const AudioBuffer *channelBuffer = &bufferList->mBuffers[channel];
        Float32 *channelData = (Float32 *)channelBuffer->mData;
        sum += channelData[frame];
      }
      monoBuffer[frame] = sum / numChannels;
    }
  }

  return monoBuffer;
}

- (Float32 *)resampleBuffer:(Float32 *)inputBuffer
                inputFrames:(UInt32)inputFrames
               outputFrames:(UInt32 *)outputFrames {
  Float64 sourceRate = _sourceFormat.mSampleRate;
  Float64 ratio = sourceRate / kTargetSampleRate;
  UInt32 newFrameLength = (UInt32)(inputFrames / ratio);

  if (newFrameLength == 0) {
    scribe_log("AudioCaptureManager", "Invalid resampled frame length",
               OS_LOG_TYPE_ERROR);
    return NULL;
  }

  // Allocate buffer for resampled data
  Float32 *resampledBuffer = (Float32 *)calloc(newFrameLength, sizeof(Float32));
  if (!resampledBuffer) {
    scribe_log("AudioCaptureManager",
               "Failed to allocate memory for resampled buffer",
               OS_LOG_TYPE_ERROR);
    return NULL;
  }

  // Perform sinc sampling
  const UInt32 windowSize = 16;
  const UInt32 halfWindow = windowSize / 2;
  const float M_2PI = 2.0f * M_PI;

  for (UInt32 newIndex = 0; newIndex < newFrameLength; newIndex++) {
    float position = newIndex * ratio;
    int32_t centerIndex = (int32_t)floorf(position);
    float fracOffset = position - centerIndex;
    float sum = 0.0f;
    float weightSum = 0.0f;

    for (int32_t i = -(int32_t)halfWindow; i <= (int32_t)halfWindow; i++) {
      int32_t sampleIndex = centerIndex + i;

      if (sampleIndex < 0 || (UInt32)sampleIndex >= inputFrames) {
        continue;
      }

      float x = fracOffset - i;
      // Use normalized sinc function
      float sincValue = (x == 0.0f) ? 1.0f : sinf(M_PI * x) / (M_PI * x);
      // Blackman window for better frequency response
      float windowValue = 0.42f -
                          0.5f * cosf(M_PI * (i + halfWindow) / halfWindow) +
                          0.08f * cosf(M_2PI * (i + halfWindow) / halfWindow);
      float weight = sincValue * windowValue;

      sum += inputBuffer[sampleIndex] * weight;
      weightSum += weight;
    }

    // Normalize by total weight
    resampledBuffer[newIndex] = weightSum > 0.0f ? sum / weightSum : 0.0f;
  }

  *outputFrames = newFrameLength;
  return resampledBuffer;
}

#pragma mark - Audio Setup Methods

- (BOOL)setupAudioTapIfNeeded:(NSError **)error {
  if (_tapUID != NULL) {
    return YES;
  }

  scribe_log("AudioCaptureManager", "Setting up audio tap");

  CATapDescription *desc =
      [[CATapDescription alloc] initMonoGlobalTapButExcludeProcesses:@[]];

  // Create a unique tap UID
  _tapUID = [NSUUID UUID];

  desc.name = [NSString stringWithFormat:@"audiorec-tap-%@", _tapUID];
  desc.UUID = _tapUID;
  desc.privateTap = true;
  desc.muteBehavior = CATapUnmuted;
  desc.exclusive = false;
  desc.mixdown = true;

  _tapObjectID = kAudioObjectUnknown;
  OSStatus ret = AudioHardwareCreateProcessTap(desc, &_tapObjectID);

  if (ret != kAudioHardwareNoError) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"audio-capture-manager"
                     code:ret
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to create audio tap"
                 }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager", "Audio tap setup successfully");
  return YES;
}

#pragma mark - Aggregate Device Setup

- (BOOL)setupAggregateDeviceIfNeeded:(NSError **)error {
  if (_aggregateDeviceID != kAudioDeviceUnknown) {
    return YES;
  }

  scribe_log("AudioCaptureManager", "Setting up aggregate device");

  // Get default input and output devices
  AudioDeviceID inputDeviceID, outputDeviceID;
  UInt32 propertySize = sizeof(AudioDeviceID);
  AudioObjectPropertyAddress propertyAddress = {
      .mSelector = kAudioHardwarePropertyDefaultInputDevice,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain};

  // Get default input device
  OSStatus status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &propertySize, &inputDeviceID);

  if (status != noErr) {
    if (error) {
      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to get default input device"
                               }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager",
             "Got input device ID: " + std::to_string(inputDeviceID));

  // Get default output device
  propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
  status =
      AudioObjectGetPropertyData(kAudioObjectSystemObject, &propertyAddress, 0,
                                 NULL, &propertySize, &outputDeviceID);

  if (status != noErr) {
    if (error) {
      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to get default output device"
                               }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager",
             "Got output device ID: " + std::to_string(outputDeviceID));

  // Get device UIDs
  CFStringRef inputUID, outputUID;
  AudioObjectPropertyAddress uidPropertyAddress = {
      .mSelector = kAudioDevicePropertyDeviceUID,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain};

  UInt32 dataSize = sizeof(CFStringRef);

  status = AudioObjectGetPropertyData(inputDeviceID, &uidPropertyAddress, 0,
                                      NULL, &dataSize, &inputUID);

  if (status != noErr) {
    if (error) {
      *error = [NSError
          errorWithDomain:@"audio-capture-manager"
                     code:status
                 userInfo:@{
                   NSLocalizedDescriptionKey : @"Failed to get input device UID"
                 }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager",
             "Got input device UID: " +
                 std::string([(__bridge NSString *)inputUID UTF8String]));

  status = AudioObjectGetPropertyData(outputDeviceID, &uidPropertyAddress, 0,
                                      NULL, &dataSize, &outputUID);

  if (status != noErr) {
    CFRelease(inputUID);
    if (error) {
      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to get output device UID"
                               }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager",
             "Got output device UID: " +
                 std::string([(__bridge NSString *)outputUID UTF8String]));

  // Get sample rates for both devices
  Float64 inputSampleRate, outputSampleRate;
  AudioObjectPropertyAddress sampleRateAddress = {
      .mSelector = kAudioDevicePropertyNominalSampleRate,
      .mScope = kAudioObjectPropertyScopeGlobal,
      .mElement = kAudioObjectPropertyElementMain};

  dataSize = sizeof(Float64);

  status = AudioObjectGetPropertyData(inputDeviceID, &sampleRateAddress, 0,
                                      NULL, &dataSize, &inputSampleRate);

  if (status != noErr) {
    CFRelease(inputUID);
    CFRelease(outputUID);
    if (error) {
      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to get input device sample rate"
                               }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager",
             "Input device sample rate: " + std::to_string(inputSampleRate));

  status = AudioObjectGetPropertyData(outputDeviceID, &sampleRateAddress, 0,
                                      NULL, &dataSize, &outputSampleRate);

  if (status != noErr) {
    CFRelease(inputUID);
    CFRelease(outputUID);
    if (error) {
      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to get output device sample rate"
                               }];
    }
    return NO;
  }

  scribe_log("AudioCaptureManager",
             "Output device sample rate: " + std::to_string(outputSampleRate));

  // Choose master device based on lower sample rate
  NSString *masterDeviceUID = inputSampleRate <= outputSampleRate
                                  ? (__bridge NSString *)inputUID
                                  : (__bridge NSString *)outputUID;
  scribe_log("AudioCaptureManager",
             "Selected master device UID: " +
                 std::string([masterDeviceUID UTF8String]) +
                 " (based on sample rate comparison: " +
                 std::to_string(inputSampleRate) +
                 " <= " + std::to_string(outputSampleRate) + ")");

  NSUUID *aggregateUID = [NSUUID UUID];
  scribe_log("AudioCaptureManager",
             "Created aggregate device UUID: " +
                 std::string([[aggregateUID UUIDString] UTF8String]));

  NSDictionary *description = @{
    @(kAudioAggregateDeviceUIDKey) : [aggregateUID UUIDString],
    @(kAudioAggregateDeviceIsPrivateKey) : @(1),
    @(kAudioAggregateDeviceIsStackedKey) : @(0),
    @(kAudioAggregateDeviceMasterSubDeviceKey) : masterDeviceUID,
    @(kAudioAggregateDeviceSubDeviceListKey) : @[
      @{
        @(kAudioSubDeviceUIDKey) : (__bridge NSString *)inputUID,
        @(kAudioSubDeviceDriftCompensationKey) : @(0),
        @(kAudioSubDeviceDriftCompensationQualityKey) :
            @(kAudioSubDeviceDriftCompensationMaxQuality),
      },
      @{
        @(kAudioSubDeviceUIDKey) : (__bridge NSString *)outputUID,
        @(kAudioSubDeviceDriftCompensationKey) : @(1),
        @(kAudioSubDeviceDriftCompensationQualityKey) :
            @(kAudioSubDeviceDriftCompensationMaxQuality),
      },
    ],
    @(kAudioAggregateDeviceTapListKey) : @[
      @{
        @(kAudioSubTapDriftCompensationKey) : @(1),
        @(kAudioSubTapUIDKey) : [_tapUID UUIDString],
      },
    ],
  };

  // Create the aggregate device
  AudioDeviceID aggregateDeviceID;
  status = AudioHardwareCreateAggregateDevice(
      (__bridge CFDictionaryRef)description, &aggregateDeviceID);

  CFRelease(inputUID);
  CFRelease(outputUID);

  if (status != noErr) {
    if (error) {
      *error = [NSError errorWithDomain:@"audio-capture-manager"
                                   code:status
                               userInfo:@{
                                 NSLocalizedDescriptionKey :
                                     @"Failed to create aggregate device"
                               }];
    }
    return NO;
  }

  // Configure buffer size for aggregate device
  AudioObjectPropertyAddress bufferSizeAddress = {
      .mSelector = kAudioDevicePropertyBufferFrameSize,
      .mScope = kAudioDevicePropertyScopeInput,
      .mElement = kAudioObjectPropertyElementMain};

  UInt32 bufferSize = kPreferredBufferSize;
  status = AudioObjectSetPropertyData(aggregateDeviceID, &bufferSizeAddress, 0,
                                      NULL, sizeof(UInt32), &bufferSize);

  if (status == noErr) {
    scribe_log("AudioCaptureManager", "Set aggregate device buffer size to: " +
                                          std::to_string(bufferSize));
  } else {
    scribe_log(
        "AudioCaptureManager",
        "Failed to set aggregate device buffer size, continuing with default",
        OS_LOG_TYPE_ERROR);
  }

  // Get and log aggregate device info
  Float64 aggregateSampleRate;
  status = AudioObjectGetPropertyData(aggregateDeviceID, &sampleRateAddress, 0,
                                      NULL, &dataSize, &aggregateSampleRate);

  if (status == noErr) {
    scribe_log("AudioCaptureManager",
               "Created aggregate device with ID: " +
                   std::to_string(aggregateDeviceID) +
                   ", sample rate: " + std::to_string(aggregateSampleRate));

    // Get format description
    AudioStreamBasicDescription format;
    UInt32 formatSize = sizeof(AudioStreamBasicDescription);
    AudioObjectPropertyAddress formatAddress = {
        .mSelector = kAudioDevicePropertyStreamFormat,
        .mScope = kAudioDevicePropertyScopeInput,
        .mElement = kAudioObjectPropertyElementMain};

    status = AudioObjectGetPropertyData(aggregateDeviceID, &formatAddress, 0,
                                        NULL, &formatSize, &format);

    if (status == noErr) {
      scribe_log("AudioCaptureManager", "Aggregate device format details:");
      scribe_log("AudioCaptureManager",
                 "- Sample rate: " + std::to_string(format.mSampleRate));
      scribe_log("AudioCaptureManager",
                 "- Format ID: " + std::to_string(format.mFormatID));
      scribe_log("AudioCaptureManager",
                 "- Format flags: " + std::to_string(format.mFormatFlags));
      scribe_log("AudioCaptureManager",
                 "- Bytes per packet: " +
                     std::to_string(format.mBytesPerPacket));
      scribe_log("AudioCaptureManager",
                 "- Frames per packet: " +
                     std::to_string(format.mFramesPerPacket));
      scribe_log("AudioCaptureManager",
                 "- Bytes per frame: " + std::to_string(format.mBytesPerFrame));
      scribe_log("AudioCaptureManager",
                 "- Channels per frame: " +
                     std::to_string(format.mChannelsPerFrame));
      scribe_log("AudioCaptureManager",
                 "- Bits per channel: " +
                     std::to_string(format.mBitsPerChannel));
      bool isInterleaved =
          !(format.mFormatFlags & kAudioFormatFlagIsNonInterleaved);
      scribe_log("AudioCaptureManager",
                 "- Is interleaved: " +
                     std::string(isInterleaved ? "yes" : "no"));
    }
    _sourceFormat = format;
  }

  _aggregateDeviceID = aggregateDeviceID;
  scribe_log("AudioCaptureManager", "Aggregate device setup successfully");
  return YES;
}

#pragma mark - Device Monitoring

- (void)startDeviceMonitoring {
  scribe_log("AudioCaptureManager", "Starting device monitoring");

  // Set up device change listener for both input and output devices
  AudioObjectPropertyAddress propertyAddress = {
      .mSelector = kAudioHardwarePropertyDefaultInputDevice,
      .mScope = kDeviceChangeScope,
      .mElement = kDeviceChangeElement};

  // Create block for device changes.
  __block AudioCaptureManager *blockSelf = self;
  _deviceChangeListener = [^(UInt32 inNumberAddresses,
                             const AudioObjectPropertyAddress *inAddresses) {
    [blockSelf handleDeviceChange];
  } copy];

  // Add listener for input device changes
  OSStatus status = AudioObjectAddPropertyListenerBlock(
      kAudioObjectSystemObject, &propertyAddress, self->_audioQueue,
      self->_deviceChangeListener);

  if (status != noErr) {
    scribe_log("AudioCaptureManager",
               "Failed to add input device change listener", OS_LOG_TYPE_ERROR);
    return;
  }

  // Add listener for output device changes
  propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
  status = AudioObjectAddPropertyListenerBlock(
      kAudioObjectSystemObject, &propertyAddress, self->_audioQueue,
      self->_deviceChangeListener);

  if (status != noErr) {
    scribe_log("AudioCaptureManager",
               "Failed to add output device change listener",
               OS_LOG_TYPE_ERROR);
    return;
  }

  scribe_log("AudioCaptureManager", "Device monitoring started successfully");
}

- (void)handleDeviceChange {
  scribe_log("AudioCaptureManager", "Handling device change");

  // If we're currently capturing, we need to recreate the audio setup
  BOOL wasCapturing = _isCapturing;
  if (wasCapturing) {
    NSError *error = nil;
    [self stopCapture:&error];
    if (error) {
      scribe_log("AudioCaptureManager",
                 std::string("Failed to stop capture after device change: ") +
                     std::string([error.localizedDescription UTF8String]),
                 OS_LOG_TYPE_ERROR);
      return;
    }
  }

  // Destroy and recreate audio resources
  [self destroyAudioResources];

  NSError *error = nil;
  if (![self setupAudioTapIfNeeded:&error]) {
    scribe_log("AudioCaptureManager",
               std::string("Failed to setup audio tap after device change: ") +
                   std::string([error.localizedDescription UTF8String]),
               OS_LOG_TYPE_ERROR);
    return;
  }

  if (![self setupAggregateDeviceIfNeeded:&error]) {
    scribe_log(
        "AudioCaptureManager",
        std::string("Failed to setup aggregate device after device change: ") +
            std::string([error.localizedDescription UTF8String]),
        OS_LOG_TYPE_ERROR);
    return;
  }

  // If we were capturing before, restart capture
  if (wasCapturing) {
    NSError *error = nil;
    [self startCapture:&error];
    if (error) {
      scribe_log("AudioCaptureManager",
                 std::string("Failed to start capture after device change: ") +
                     std::string([error.localizedDescription UTF8String]),
                 OS_LOG_TYPE_ERROR);
      return;
    }
  }

  scribe_log("AudioCaptureManager", "Device change handled successfully");
}

- (void)stopDeviceMonitoring {
  scribe_log("AudioCaptureManager", "Stopping device monitoring");

  if (_deviceChangeListener) {
    // REmove input device listener
    AudioObjectPropertyAddress propertyAddress = {
        .mSelector = kAudioHardwarePropertyDefaultInputDevice,
        .mScope = kDeviceChangeScope,
        .mElement = kDeviceChangeElement};

    AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject,
                                           &propertyAddress, _audioQueue,
                                           _deviceChangeListener);

    // Remove output device listener
    propertyAddress.mSelector = kAudioHardwarePropertyDefaultOutputDevice;
    AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject,
                                           &propertyAddress, _audioQueue,
                                           _deviceChangeListener);

    [_deviceChangeListener release];
    _deviceChangeListener = nil;
  }

  scribe_log("AudioCaptureManager", "Device monitoring stopped");
}

- (void)destroyAudioResources {
  scribe_log("AudioCaptureManager", "Destroying audio resources");

  if (_deviceProcID && _aggregateDeviceID != kAudioDeviceUnknown) {
    AudioDeviceDestroyIOProcID(_aggregateDeviceID, _deviceProcID);
    _deviceProcID = NULL;
  }

  if (_tapObjectID != 0) {
    AudioHardwareDestroyProcessTap(_tapObjectID);
    _tapObjectID = 0;
  }

  if (_tapUID) {
    _tapUID = NULL;
  }

  if (_aggregateDeviceID != kAudioDeviceUnknown) {
    AudioHardwareDestroyAggregateDevice(_aggregateDeviceID);
    _aggregateDeviceID = kAudioDeviceUnknown;
  }

  scribe_log("AudioCaptureManager", "Audio resources destroyed");
}

#pragma mark - TCC Framework Methods

- (void)initializeTCCFramework {
  scribe_log("AudioCaptureManager", "Initializing TCC framework");

  // Load TCC framework
  NSString *tccPath =
      @"/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC";
  _tccHandle = dlopen([tccPath UTF8String], RTLD_NOW);
  if (!_tccHandle) {
    scribe_log("AudioCaptureManager",
               std::string("Failed to load TCC framework: ") +
                   std::string(dlerror()),
               OS_LOG_TYPE_ERROR);
    return;
  }
  scribe_log("AudioCaptureManager", "Successfully loaded TCC framework");

  // Get function pointers
  _preflightFunc =
      (TCCPreflightFuncType)dlsym(_tccHandle, "TCCAccessPreflight");
  _requestFunc = (TCCRequestFuncType)dlsym(_tccHandle, "TCCAccessRequest");

  if (!_preflightFunc || !_requestFunc) {
    scribe_log("AudioCaptureManager",
               std::string("Failed to get TCC function pointers: ") +
                   std::string(dlerror()),
               OS_LOG_TYPE_ERROR);
    dlclose(_tccHandle);
    _tccHandle = NULL;
    return;
  }
  scribe_log("AudioCaptureManager", "Successfully initialized TCC functions");
}

- (int)checkTCCPermission:(NSString *)service {
  scribe_log("AudioCaptureManager", "Checking TCC permission for service: " +
                                        std::string([service UTF8String]));

  if (!_preflightFunc) {
    scribe_log("AudioCaptureManager", "TCC preflight function not available",
               OS_LOG_TYPE_ERROR);
    return PermissionStatusNotDetermined; // Not determined
  }

  auto result = _preflightFunc((__bridge CFStringRef)service, NULL);

  scribe_log("AudioCaptureManager",
             "TCC permission result: " + std::to_string(result));

  return result;
}

- (void)requestTCCPermission:(NSString *)service
                  completion:(void (^)(BOOL granted))completion {
  scribe_log("AudioCaptureManager", "Requesting TCC permission for service: " +
                                        std::string([service UTF8String]));

  if (!_requestFunc) {
    scribe_log("AudioCaptureManager", "TCC request function not available",
               OS_LOG_TYPE_ERROR);
    completion(NO);
    return;
  }

  _requestFunc((__bridge CFStringRef)service, NULL, ^(BOOL granted) {
    scribe_log(
        "AudioCaptureManager",
        "TCC permission request for " + std::string([service UTF8String]) +
            " completed with result: " + (granted ? "granted" : "denied"));
    completion(granted);
  });
}

#pragma mark - Permission Methods

- (PermissionStatus)getPermission {
  scribe_log("AudioCaptureManager", "Getting permission");

  // Check audio recording permission using TCC
  auto audioResult =
      (PermissionStatus)[self checkTCCPermission:@"kTCCServiceAudioCapture"];

  PermissionStatus audioPermissionStatus(audioResult);

  scribe_log("AudioCaptureManager",
             "System audio permission status: " + std::to_string(audioResult));

  return audioPermissionStatus;
}

- (void)requestPermission:(void (^)(PermissionStatus))completion {
  scribe_log("AudioCaptureManager", "Requesting permission");

  [self requestTCCPermission:@"kTCCServiceAudioCapture"
                  completion:^(BOOL granted) {
                    auto status =
                        granted ? PermissionStatus::PermissionStatusAuthorized
                                : PermissionStatus::PermissionStatusDenied;
                    scribe_log("AudioCaptureManager",
                               "System audio permission request completed with "
                               "status: " +
                                   std::to_string(status));
                    completion(status);
                  }];
}

@end
