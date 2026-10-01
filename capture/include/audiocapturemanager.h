/**
 * @file audiocapturemanager.h
 * @brief Core audio management and capture functionality for macOS.
 *
 * This class provides a high-level interface for capturing audio on macOS.
 * It handles device permissions, audio setup, and streaming capture.
 */

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreAudio/CoreAudio.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

/**
 * @enum PermissionStatus
 * @brief Represents the current status of audio permission.
 */
typedef NS_ENUM(NSInteger, PermissionStatus) {
  PermissionStatusAuthorized,
  PermissionStatusDenied,
  PermissionStatusNotDetermined,
  PermissionStatusRestricted
};

// TCC function types
typedef int (*TCCPreflightFuncType)(CFStringRef service,
                                    CFDictionaryRef options);
typedef void (*TCCRequestFuncType)(CFStringRef service, CFDictionaryRef options,
                                   void (^completionHandler)(BOOL granted));

/**
 * @class AudioCaptureManager
 * @brief Manages permissions for audio device access and capture on macOS.
 */
@interface AudioCaptureManager : NSObject {
  void *_tccHandle;
  TCCPreflightFuncType _preflightFunc;
  TCCRequestFuncType _requestFunc;

  // Audio properties
  AudioDeviceID _aggregateDeviceID;
  AudioDeviceIOProcID _deviceProcID;
  AudioStreamBasicDescription _sourceFormat;
  AudioObjectPropertyListenerBlock _deviceChangeListener;

  // State
  BOOL _isCapturing;

  // Queue for audio operations
  dispatch_queue_t _audioQueue;

  // Callback for target audio format configuration
  void (^_audioFormatCallback)(Float64, UInt32);

  // Callback for audio data
  void (^_audioDataCallback)(NSData *audioData);

  // Tap properties
  NSUUID *_tapUID;
  AudioObjectID _tapObjectID;
}

/**
 * @brief returns the singleton instance of AudioCaptureManager
 * @return The shared AudioCaptureManager instance.
 */
+ (instancetype)sharedInstance;

/**
 * @name Audio Control Methods
 * Methods for controlling audio capture and streaming.
 */

/**
 * @brief Start capturing audio from the system.
 * @param error Pointer to `NSError` object that will be set if an error occurs.
 * @param `YES` if capture started successfully, `NO` otherwise.
 * @note Requires proper permissions and device setup before starting.
 */
- (BOOL)startCapture:(NSError **)error;

/**
 * @brief Stop the current audio capture session.
 * @param error Pointer to `NSError` object that will be set if an error occurs.
 * @return `YES` if capture stopped successfully, `NO` otherwise.
 */
- (BOOL)stopCapture:(NSError **)error;

/**
 * @brief Set the callback function for configuring the audio engine to
 * capture audio data.
 * @param callback Block that will be called with the sample rate and number
 * of channels of the data delivered to the audio data callback.
 * @note The callback is invoked on the main thread each time capture starts,
 * before any audio data is delivered.
 */
- (void)setAudioFormatCallback:(void (^)(Float64 sampleRate,
                                         UInt32 numChannels))callback;

/**
 * @brief Set the callback function for receiving captured audio data.
 * @param callback Block that will be called with captured audio data.
 * @note The callback is invoked on a dedicated audio queue thread.
 */
- (void)setAudioDataCallback:(void (^)(NSData *audioData))callback;

/**
 * @name Audio Setup and Management Methods
 */

/**
 * @brief Set up audio tap if not already configured.
 * @param error Pointer to `NSError` object that will be set if an error occurs.
 * @return `YES` if startup was successful or already done, `NO` otherwise.
 */
- (BOOL)setupAudioTapIfNeeded:(NSError **)error;

/**
 * @brief Set up aggregate device if needed for audio capture.
 * @param `error` Pointer to `NSError` object that will be set if an error
 * occurs.
 * @return `YES` if setup was successful or already done, `NO` otherwise.
 */
- (BOOL)setupAggregateDeviceIfNeeded:(NSError **)error;

/**
 * @brief Clean up and release audio resources.
 * @note Called internally during deallocation or when stopping capture.
 */
- (void)destroyAudioResources;

/**
 * @brief Start monitoring for audio device changes.
 * @note Sets up listeners for device configuration changes.
 */
- (void)startDeviceMonitoring;

/**
 * @brief Stop monitoring for audio device changes.
 * @note Removes device configuration change listeners.
 */
- (void)stopDeviceMonitoring;

/**
 * @brief Handle changes in audio device configuration.
 * @not Called automatically when device changes are detected.
 */
- (void)handleDeviceChange;

/**
 * @name Permission Methods
 */

/**
 * @brief Get current permission status for audio devices.
 * @return `PermissionStatus` containing permission status.
 */
- (PermissionStatus)getPermission;

/**
 * @brief Request permission to access system audio.
 * @param completion Block called with permission result.
 */
- (void)requestPermission:(void (^)(PermissionStatus))completion;

/**
 * @name Private TCC (Transparency, Consent, and Control) Methods
 */

/**
 * @brief Intialize the TCC framework for permission handling.
 * @note This is called internally during initialization.
 */
- (void)initializeTCCFramework;

/**
 * @brief Check current TCC permission status for a service.
 * @param service The service identifier to check.
 * @return `int` representing the permission status.
 */
- (int)checkTCCPermission:(NSString *)service;

/**
 * @brief Request TCC permission for a specific service.
 * @param service The service identifier to request permission for.
 * @param completion Block called with the grant status.
 */
- (void)requestTCCPermission:(NSString *)service
                  completion:(void (^)(BOOL granted))completion;
@end
