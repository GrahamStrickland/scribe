#include <QGuiApplication>
#include <QQmlApplicationEngine>

int main(int argc, char *argv[]) {
  // Qt Multimedia defaults to its FFmpeg backend; use AVFoundation so playback
  // matches the native macOS player. An explicit environment setting wins.
  if (qEnvironmentVariableIsEmpty("QT_MEDIA_BACKEND")) {
    qputenv("QT_MEDIA_BACKEND", "darwin");
  }

  QGuiApplication app(argc, argv);
  QGuiApplication::setApplicationName("Scribe");
  QGuiApplication::setOrganizationName("Graham Strickland");
  QGuiApplication::setApplicationVersion(APP_VERSION);

  QQmlApplicationEngine engine;
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [] { QCoreApplication::exit(-1); }, Qt::QueuedConnection);
  engine.loadFromModule("ScribeUI", "Main");

  return app.exec();
}
