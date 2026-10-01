#import "logutil.h"

#import <mutex>
#import <unordered_map>

#ifdef scribe_LOG_STDERR
#import <cstdio>
#import <unistd.h>

namespace {
// Human-readable name and ANSI color used when mirroring a log type to stderr.
struct stderr_style {
  const char *name;
  const char *color; // ANSI SGR sequence, or "" for the terminal default
};

stderr_style StyleForType(os_log_type_t type) {
  switch (type) {
  case OS_LOG_TYPE_FAULT:
    return {"fault", "\033[91m"}; // bright red
  case OS_LOG_TYPE_ERROR:
    return {"error", "\033[93m"}; // yellow
  case OS_LOG_TYPE_DEBUG:
    return {"debug", "\033[90m"}; // gray
  case OS_LOG_TYPE_INFO:
    return {"info", "\033[36m"}; // cyan
  default:
    return {"default", ""}; // OS_LOG_TYPE_DEFAULT
  }
}
} // namespace
#endif // scribe_LOG_STDERR

namespace {
// Returns a process-lifetime os_log object for the given component, creating it
// on first use. Console groups messages by category, so each component gets its
// own log object. The objects are intentionally never released: there is a
// small, fixed set of components and they live for the life of the process.
os_log_t log_for_component(const std::string &component) {
  static std::mutex mutex;
  static std::unordered_map<std::string, os_log_t> logs;

  std::lock_guard<std::mutex> guard(mutex);
  auto it = logs.find(component);
  if (it == logs.end()) {
    it = logs.emplace(component, os_log_create("com.scribe", component.c_str()))
             .first;
  }
  return it->second;
}
} // namespace

void scribe_log(const std::string &component, const std::string &message,
                os_log_type_t type) {
  os_log_with_type(log_for_component(component), type, "%{public}s",
                   message.c_str());

#ifdef scribe_LOG_STDERR
  // Debug builds also mirror to stderr, since os_log does not write to the
  // terminal. ANSI colors are only emitted when stderr is an interactive
  // terminal, so redirected logs stay free of escape codes.
  const stderr_style style = StyleForType(type);
  const bool tty = isatty(fileno(stderr)) != 0;
  fprintf(stderr, "%s[%s] [%s] %s%s\n", tty ? style.color : "", style.name,
          component.c_str(), message.c_str(), tty ? "\033[0m" : "");
#endif
}
