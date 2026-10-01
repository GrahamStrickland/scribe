#ifndef AUDIO_ENGINE_H
#define AUDIO_ENGINE_H

#include <cstdint>
#include <string>
#include <vector>

namespace audio {
/**
 * @class audio_engine
 * @brief Manages audio data capture and writing audio data to file.
 */
class audio_engine {
public:
  explicit audio_engine(double total_seconds);

  /**
   * @brief Set the audio format for captured PCM audio data.
   * @param sample_rate Audio sample rate from device captured.
   * @param num_channels Number of channels per frame from audio device
   * captured.
   * @note called using a callback in the AudioCaptureManager.
   */
  void configure_format(double sample_rate, uint32_t num_channels);

  /**
   * @brief Captured raw PCM audio data in internal buffer.
   * @param raw_bytes Raw bytes of PCM audio data in 32-bit floating point
   * format.
   * @param byte_length Number of bytes to be captured.
   * @note Called using a callback in the AudioCaptureManager.
   */
  void capture_audio_data(const void *raw_bytes, std::size_t byte_length);

  /**
   * @brief Export captured raw PCM audio data to .wav file.
   * @param file_name File name captured in system file dialog.
   * @param error_msg Optional error message if function returns `false`.
   * @return `true` if file was able to be opened and written to, `false`
   * otherwise.
   */
  bool export_audio_data_to_wav(const std::string &filename,
                                std::string &error_msg);
  /**
   * @note Convenience function for testing.
   */
  std::size_t size_captured() const;

private:
  double m_total_seconds;
  std::vector<float> m_pcm_buffer;
  double m_sample_rate = 48000.0;
  uint32_t m_num_channels = 1;
};
} // end namespace audio

#endif // AUDIO_ENGINE_H
