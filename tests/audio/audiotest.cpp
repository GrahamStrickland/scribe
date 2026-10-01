#include <filesystem>
#include <fstream>
#include <string>

#include <catch2/catch_test_macros.hpp>

#include "audioengine.h"
#include "wavheader.h"

namespace fs = std::filesystem;

class mock_audio_data {
public:
  mock_audio_data() {
    float fake_data[4] = {0.1, 0.2, 0.3, 0.4};
    _audio_data = new float[4];

    for (std::size_t i = 0; i < 4; i++) {
      _audio_data[i] = fake_data[i];
    }
  }

  ~mock_audio_data() { delete[] _audio_data; }

  float *get_audio_data() { return _audio_data; }

private:
  float *_audio_data;
};

struct temp_file_guard {
  fs::path path;

  temp_file_guard(const std::string &filename) {
    path = fs::temp_directory_path() / filename;
  }

  ~temp_file_guard() {
    if (fs::exists(path)) {
      fs::remove(path);
    }
  }
};

TEST_CASE("AudioEngine captures audio data correctly", "[audio]") {
  auto audio_engine = audio::audio_engine(1.0);

  mock_audio_data data_mock{};
  auto audio_data = data_mock.get_audio_data();

  audio_engine.capture_audio_data(audio_data, 4 * sizeof(float));
  REQUIRE(audio_engine.size_captured() == 4);
};

TEST_CASE("AudioEngine writes audio data to file correctly", "[audio]") {
  temp_file_guard temp("test_file.wav");
  auto audio_engine = audio::audio_engine(1.0);
  std::string error_msg;

  mock_audio_data data_mock{};
  auto audio_data = data_mock.get_audio_data();
  audio_engine.capture_audio_data(audio_data, 4 * sizeof(float));
  auto success =
      audio_engine.export_audio_data_to_wav(temp.path.string(), error_msg);

  REQUIRE(success);
  REQUIRE(fs::exists(temp.path));

  std::ifstream in(temp.path);
  std::string content;
  std::getline(in, content);
  REQUIRE(content.length() > 0);
}

TEST_CASE("AudioEngine fails to write audio data to existing file", "[audio]") {
  temp_file_guard temp("test_file.wav");
  auto audio_engine = audio::audio_engine(1.0);
  std::string error_msg;

  std::ofstream out(temp.path.string());
  out << "Test Data";

  REQUIRE(fs::exists(temp.path));

  fs::permissions(temp.path, fs::perms::owner_read | fs::perms::group_read |
                                 fs::perms::others_read);

  mock_audio_data data_mock{};
  auto audio_data = data_mock.get_audio_data();
  audio_engine.capture_audio_data(audio_data, 4 * sizeof(float));
  auto success =
      audio_engine.export_audio_data_to_wav(temp.path.string(), error_msg);

  REQUIRE(!success);
}

TEST_CASE("AudioEngine writes configured format to WAV header", "[audio]") {
  temp_file_guard temp("test_format.wav");
  auto audio_engine = audio::audio_engine(1.0);
  std::string error_msg;

  audio_engine.configure_format(44100.0, 2);

  mock_audio_data data_mock{};
  audio_engine.capture_audio_data(data_mock.get_audio_data(),
                                  4 * sizeof(float));
  REQUIRE(audio_engine.export_audio_data_to_wav(temp.path.string(), error_msg));

  std::ifstream file(temp.path, std::ios::binary);
  wav_header header;
  file.read(reinterpret_cast<char *>(&header), sizeof(wav_header));
  REQUIRE(file.gcount() == sizeof(wav_header));

  REQUIRE(header.sample_rate == 44100);
  REQUIRE(header.num_channels == 2);
  REQUIRE(header.block_align == 8);
  REQUIRE(header.byte_rate == 352800);
  REQUIRE(header.sub_chunk2_size == 4 * sizeof(float));
}
