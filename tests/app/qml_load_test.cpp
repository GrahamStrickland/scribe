#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlError>
#include <QStringList>

#include <catch2/catch_test_macros.hpp>

// Run with QT_QPA_PLATFORM=offscreen (set by tests/CMakeLists.txt).
TEST_CASE("Main.qml loads without errors or warnings", "[qml]") {
  static int argc = 1;
  static char appName[] = "qml_load_test";
  static char *argv[] = {appName, nullptr};
  QGuiApplication app(argc, argv);

  QQmlApplicationEngine engine;
  QStringList warnings;
  QObject::connect(&engine, &QQmlApplicationEngine::warnings,
                   [&](const QList<QQmlError> &errors) {
                     for (const QQmlError &error : errors) {
                       warnings << error.toString();
                     }
                   });

  engine.loadFromModule("ScribeUI", "Main");
  QCoreApplication::processEvents();

  INFO(warnings.join('\n').toStdString());
  REQUIRE(engine.rootObjects().size() == 1);
  REQUIRE(warnings.isEmpty());
}
