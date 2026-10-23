// pocknix-ui-host <app> | <path/to/Main.qml> - started through the pocknix-ui wrapper only.
#include <QByteArray>
#include <QFileInfo>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QRegularExpression>
#include <QScreen>
#include <QStandardPaths>
#include <QUrl>

#include <cmath>
#include <cstdio>
#include <unistd.h>

// 1x = 160 dpi, Android's baseline density. Without a physical size the short side counts as
// 540 logical pixels.
static qreal gamescopeScale(const QScreen *screen)
{
    if (!screen)
        return 1.0;
    const QSizeF mm = screen->physicalSize();
    const qreal f = mm.width() >= 40 && mm.height() >= 40
        ? screen->physicalDotsPerInch() / 160.0
        : qMin(screen->size().width(), screen->size().height()) / 540.0;
    return qMax(1.0, std::round(f * 4) / 4);
}

int main(int argc, char *argv[])
{
    const QString arg = argc == 2 ? QString::fromLocal8Bit(argv[1]) : QString();
    QString name = arg;
    QString qml;
    if (arg.contains(u'/')) {
        qml = QFileInfo(arg).absoluteFilePath();
        name = QStringLiteral("ui");
    } else if (QRegularExpression(QStringLiteral("^[a-z0-9-]+$")).match(arg).hasMatch()) {
        qml = QStringLiteral("/usr/share/pocknix-%1/qml/Main.qml").arg(arg);
    }
    if (qml.isEmpty()) {
        std::fputs("usage: pocknix-ui <app> | <path/to/Main.qml>\n", stderr);
        return 2;
    }

    const bool gamescope = qEnvironmentVariableIsSet("GAMESCOPE_WAYLAND_DISPLAY");
    // Wayland gets real touch under gamescope; on xcb touch arrives as Steam's emulated pointer
    // (taps only), so xcb is only the fallback when no compositor socket is reachable.
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM"))
        qputenv("QT_QPA_PLATFORM", "wayland;xcb");
    if (gamescope)
        qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1");
    // Basic draws every control from the window palette, which Theme.qml sets in both sessions;
    // Breeze reads Plasma's colour scheme, which gamescope does not have.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE"))
        QQuickStyle::setStyle(QStringLiteral("Basic"));

    QGuiApplication app(argc, argv);
    // The Wayland app id: Plasma finds the icon and taskbar entry through the .desktop name.
    app.setDesktopFileName(QStringLiteral("pocknix-") + name);
    // A platform plugin without a Unix theme names no icon theme and searches only :/icons, so
    // theme icon names would resolve to nothing.
    QStringList iconPaths = QIcon::themeSearchPaths();
    for (const QString &dir : QStandardPaths::standardLocations(QStandardPaths::GenericDataLocation)) {
        if (!iconPaths.contains(dir + u"/icons"))
            iconPaths.append(dir + u"/icons");
    }
    QIcon::setThemeSearchPaths(iconPaths);
    if (QIcon::themeName().isEmpty() || QIcon::themeName() == u"hicolor")
        QIcon::setThemeName(QStringLiteral("breeze-dark"));

    // gamescope reports scale 1, and Qt reads QT_SCALE_FACTOR only at startup: set it, start over.
    if (gamescope && qEnvironmentVariableIsEmpty("QT_SCALE_FACTOR")) {
        const qreal f = gamescopeScale(app.primaryScreen());
        if (f > 1.0) {
            qputenv("QT_SCALE_FACTOR", QByteArray::number(f));
            execv("/proc/self/exe", argv);
        }
    }

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.load(QUrl::fromLocalFile(qml));
    return app.exec();
}
