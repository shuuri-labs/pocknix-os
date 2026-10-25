#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// {root: true} runs through pkexec, and only for /usr/bin/pocknix-* programs.
class Job : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int exitCode READ exitCode NOTIFY runningChanged)
    Q_PROPERTY(QString output READ output NOTIFY runningChanged)
    Q_PROPERTY(QString error READ error NOTIFY runningChanged)
    Q_PROPERTY(QString phase READ phase NOTIFY progressChanged)
    Q_PROPERTY(QString text READ text NOTIFY progressChanged)
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)

public:
    explicit Job(QObject *parent = nullptr);
    ~Job() override;

    bool running() const { return m_proc != nullptr; }
    int exitCode() const { return m_exitCode; }
    QString output() const { return m_output; }
    QString error() const { return m_error; }
    QString phase() const { return m_phase; }
    QString text() const { return m_text; }
    qreal progress() const { return m_progress; }

    // options: root (bool), input (bool: keep stdin open; closing it is the cancel request)
    Q_INVOKABLE bool start(const QStringList &argv, const QVariantMap &options = {});
    Q_INVOKABLE void send(const QString &line);
    Q_INVOKABLE void closeInput();

signals:
    void runningChanged();
    void progressChanged();
    void line(const QString &text);
    void event(const QVariantMap &data);
    void finished(int exitCode);

private:
    void readChannel(QProcess::ProcessChannel channel);
    void handleLine(const QString &text, bool fromStdout);
    void done(int exitCode, const QString &error);

    QProcess *m_proc = nullptr;
    bool m_root = false;
    QStringList m_pending;
    QVariantMap m_pendingOptions;
    QByteArray m_partial[2];
    QStringList m_tail;
    int m_exitCode = 0;
    QString m_output;
    QString m_error;
    QString m_phase;
    QString m_text;
    qreal m_progress = -1;
};
