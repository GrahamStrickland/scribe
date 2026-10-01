#include "recordingcontroller.h"

#include <QPointer>

#include <string>

#include "logutil.h"

RecordingController::RecordingController(QObject *parent) : QObject(parent) {}

bool RecordingController::isRecording() const { return m_recording; }

void RecordingController::toggleRecording() {
  if (m_recording) {
    stopRecording();
  } else {
    startRecording();
  }
}

void RecordingController::startRecording() {
  if (m_recording) {
    return;
  }

  const AudioManager::PermissionStatus status = m_audioManager.getPermission();
  if (status == AudioManager::Authorized) {
    beginCapture();
    return;
  }
  if (status == AudioManager::Denied || status == AudioManager::Restricted) {
    emit permissionDenied();
    return;
  }

  // NotDetermined: returns immediately; the result arrives on the main thread.
  // The controller may be destroyed while the system prompt is showing.
  QPointer<RecordingController> self(this);
  m_audioManager.requestPermission(
      [self](AudioManager::PermissionStatus result) {
        if (!self) {
          return;
        }
        if (result == AudioManager::Authorized) {
          self->beginCapture();
        } else {
          emit self->permissionDenied();
        }
      });
}

void RecordingController::stopRecording() {
  if (!m_recording) {
    return;
  }

  if (!m_audioManager.stopCapture()) {
    emit errorOccurred(tr("Failed to stop recording."));
    return;
  }

  scribe_log("RecordingController", "Stopping recording");
  m_recording = false;
  emit recordingChanged();
  emit saveRequested();
}

bool RecordingController::saveRecording(const QUrl &fileUrl) {
  if (!fileUrl.isLocalFile()) {
    emit errorOccurred(tr("Recordings can only be saved to a local file."));
    return false;
  }

  std::string errorMessage;
  const std::string path = fileUrl.toLocalFile().toStdString();
  if (!m_audioManager.writeCapturedAudio(path, errorMessage)) {
    emit errorOccurred(QString::fromStdString(errorMessage));
    return false;
  }
  return true;
}

void RecordingController::beginCapture() {
  if (!m_audioManager.startCapture()) {
    emit errorOccurred(tr("Failed to start recording."));
    return;
  }

  scribe_log("RecordingController",
             "Audio capture authorized - starting recording");
  m_recording = true;
  emit recordingChanged();
}
