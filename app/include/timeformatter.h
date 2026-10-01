#ifndef TIMEFORMATTER_H
#define TIMEFORMATTER_H

#include <QObject>
#include <QString>
#include <QtQmlIntegration>

#include "time_format.h"

/**
 * @class TimeFormatter
 * @brief QML singleton exposing `scribe::format_to_minutes`.
 */
class TimeFormatter : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit TimeFormatter(QObject *parent = nullptr) : QObject(parent) {}

  /**
   * @brief Format a duration in milliseconds as "M:SS.mmm".
   */
  Q_INVOKABLE static QString toMinutes(qint64 milliseconds) {
    return QString::fromStdString(scribe::format_to_minutes(milliseconds));
  }
};

#endif // TIMEFORMATTER_H
