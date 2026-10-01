/**
 * @file logutil.h
 * @brief Logging utility for Scribe.
 *
 * Provides a simple logging interface that can be used throughout the native
 * modules to log messages with different severity levels. Messages are emitted
 * through Apple's unified logging system (`os_log`), so they can be viewed and
 * filtered in Console.app and colorized by their os_log type.
 */

#import <os/log.h>
#import <string>

/**
 * @brief Log a message with a specified severity level.
 *
 * This function provides a consistent way to log messages across the native
 * module. It can be used for debugging, error reporting, and general status
 * updates. Messages are grouped by @p component (used as the os_log category)
 * under the "com.scribe" subsystem.
 *
 * The @p type is an os_log_type_t, which both controls how Console.app renders
 * the message and lets the compiler reject invalid levels:
 *   - OS_LOG_TYPE_FAULT    serious fault (red highlight in Console)
 *   - OS_LOG_TYPE_ERROR    error (yellow highlight in Console)
 *   - OS_LOG_TYPE_DEFAULT  general message; persisted and shown by default
 *   - OS_LOG_TYPE_INFO     informational; only captured while streaming
 *   - OS_LOG_TYPE_DEBUG    debug; only captured when debug logging is enabled
 *
 * In debug builds (or when the CMake option scribe_LOG_STDERR is set) messages
 * are additionally mirrored to stderr, since os_log does not write to the
 * terminal on its own.
 *
 * @param component The application component generating the log
 * @param message The message to log
 * @param type The severity level of the message (default: OS_LOG_TYPE_DEFAULT)
 *
 * Example usage:
 * @code
 *   ScribeLog("AudioCapture", "Starting audio capture");
 *   ScribeLog("AudioCapture", "Failed to initialize device",
 *              OS_LOG_TYPE_ERROR);
 * @endcode
 */
void scribe_log(const std::string &component, const std::string &message,
                os_log_type_t type = OS_LOG_TYPE_DEFAULT);
