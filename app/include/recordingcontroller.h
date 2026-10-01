#ifndef RECORDINGCONTROLLER_H
#define RECORDINGCONTROLLER_H

#include <QObject>
#include <QString>
#include <QUrl>
#include <QtQmlIntegration>

#include "audiomanager.h"

/**
 * @file recordingcontroller.h
 * @brief QML-facing recording state machine built on `AudioManager`.
 */

/**
 * @class RecordingController
 * @brief Exposes system-audio recording to QML.
 *
 * Owns an `AudioManager` and drives the record -> stop -> save flow: checking
 * and requesting capture permission, starting and stopping capture, and
 * writing the captured audio to a file the user chooses. `AudioManager` stays
 * free of Qt so it can be tested on its own; this class only adapts it to
 * signals and properties.
 */
class RecordingController : public QObject {
  Q_OBJECT
  QML_ELEMENT

  Q_PROPERTY(bool recording READ isRecording NOTIFY recordingChanged)

public:
  explicit RecordingController(QObject *parent = nullptr);

  /**
   * @brief Whether system audio is currently being captured.
   */
  bool isRecording() const;

  /**
   * @brief Start recording if idle, otherwise stop.
   */
  Q_INVOKABLE void toggleRecording();

  /**
   * @brief Start recording, requesting capture permission first if needed.
   *
   * Emits `permissionDenied()` if permission is denied or restricted, or
   * `recordingChanged()` once capture starts. If the user has not yet been
   * asked, the system prompt is shown and recording starts asynchronously.
   */
  Q_INVOKABLE void startRecording();

  /**
   * @brief Stop recording and emit `saveRequested()` so the UI can ask where
   * to write the captured audio.
   */
  Q_INVOKABLE void stopRecording();

  /**
   * @brief Write the captured audio to `fileUrl` as a WAV file.
   * @param fileUrl Local file URL chosen by the user.
   * @return `true` on success; otherwise emits `errorOccurred()` and returns
   * `false`.
   */
  Q_INVOKABLE bool saveRecording(const QUrl &fileUrl);

signals:
  void recordingChanged();
  void permissionDenied();
  void saveRequested();
  void errorOccurred(const QString &message);

private:
  void beginCapture();

  AudioManager m_audioManager;
  bool m_recording = false;
};

#endif // RECORDINGCONTROLLER_H
