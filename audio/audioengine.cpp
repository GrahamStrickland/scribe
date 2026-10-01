#include <cerrno>
#include <cstring>
#include <fstream>
#include <iostream>

#include "audioengine.h"
#include "logutil.h"
#include "wavheader.h"

namespace audio {
audio_engine::audio_engine(double total_seconds)
    : m_total_seconds{total_seconds == 0.0 ? 3600.0 : total_seconds} {
  scribe_log("audio_engine", "Allocating buffer for " +
                                 std::to_string(m_total_seconds) +
                                 "s total audio capture time");
}

void audio_engine::configure_format(double sample_rate, uint32_t num_channels) {
  scribe_log("audio_engine",
             "Setting sample rate to " + std::to_string(sample_rate));
  m_sample_rate = sample_rate;
  scribe_log("audio_engine",
             "Setting number of channels to " + std::to_string(num_channels));
  m_num_channels = num_channels;

  std::size_t total_samples = static_cast<std::size_t>(
      m_total_seconds * m_sample_rate * m_num_channels);
  std::size_t safety_padding =
      static_cast<std::size_t>(5.0 * m_sample_rate * m_num_channels);
  m_pcm_buffer.reserve(total_samples + safety_padding);

  std::size_t total_bytes = m_pcm_buffer.capacity() * sizeof(float);
  scribe_log("audio_engine",
             "Allocated " + std::to_string(total_bytes) + " bytes");
}

void audio_engine::capture_audio_data(const void *raw_bytes,
                                      std::size_t byte_length) {
  const float *sample_ptr = static_cast<const float *>(raw_bytes);
  const std::size_t num_samples = byte_length / sizeof(float);
  m_pcm_buffer.insert(m_pcm_buffer.end(), sample_ptr, sample_ptr + num_samples);
}

bool audio_engine::export_audio_data_to_wav(const std::string &filename,
                                            std::string &error_msg) {
  std::ofstream out_file(filename, std::ios::binary);
  if (!out_file.is_open()) {
    error_msg = std::string("Failed to write to file " + filename + ": " +
                            std::strerror(errno));
    return false;
  }

  error_msg = std::string("");

  // Calculate metadata sizes based on input parameters
  uint32_t data_byte_size =
      static_cast<uint32_t>(m_pcm_buffer.size() * sizeof(float));
  wav_header header;
  header.num_channels = m_num_channels;
  header.sample_rate = m_sample_rate;
  header.bits_per_sample = 32;
  header.audio_format = 3; // Critical flag for 32-bit floating point audio

  header.block_align = m_num_channels * (header.bits_per_sample / 8);
  header.byte_rate = m_sample_rate * header.block_align;
  header.sub_chunk2_size = data_byte_size;
  header.chunk_size =
      36 + data_byte_size; // Header overhead (36) + data payload

  out_file.write(reinterpret_cast<const char *>(&header), sizeof(wav_header));
  out_file.write(reinterpret_cast<const char *>(m_pcm_buffer.data()),
                 data_byte_size);

  out_file.close();

  scribe_log("audio_engine", "Wrote audio data (" +
                                 std::to_string(data_byte_size) +
                                 " bytes) to file " + filename);

  return true;
}

std::size_t audio_engine::size_captured() const { return m_pcm_buffer.size(); }
} // end namespace audio
