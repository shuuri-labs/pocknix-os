#include "job.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

namespace {
const QString kMark = QStringLiteral("POCKNIX:");
constexpr qsizetype kTailLines = 3;
}

Job::Job(QObject *parent)
    : QObject(parent)
{
}

// QProcess's destructor kills its child, then waits up to 30 s: a root child refuses the kill.
// With the pipes closed the root CLI dies on its next write; pacman lives in a pocknix-job unit.
Job::~Job()
{
    if (!m_proc || !m_root)
        return;
    m_proc->disconnect(this);
    m_proc->closeReadChannel(QProcess::StandardOutput);
    m_proc->closeReadChannel(QProcess::StandardError);
    m_proc->closeWriteChannel();
    m_proc->setParent(nullptr);
}

bool Job::start(const QStringList &argv, const QVariantMap &options)
{
    if (m_proc || argv.isEmpty())
        return false;
    static const QRegularExpression rootProgram(QStringLiteral("^/usr/bin/pocknix-[a-z0-9-]+$"));
    const bool root = options.value(QStringLiteral("root")).toBool();

    m_exitCode = 0;
    m_output.clear();
    m_error.clear();
    m_tail.clear();
    m_partial[0].clear();
    m_partial[1].clear();
    m_phase.clear();
    m_text.clear();
    m_progress = -1;
    emit progressChanged();

    if (root && !rootProgram.match(argv.first()).hasMatch()) {
        m_exitCode = 1;
        m_error = tr("Refusing to run %1 as root").arg(argv.first());
        emit runningChanged();
        emit finished(m_exitCode);
        return false;
    }

    m_root = root;
    m_proc = new QProcess(this);
    connect(m_proc, &QProcess::readyReadStandardOutput, this,
            [this] { readChannel(QProcess::StandardOutput); });
    connect(m_proc, &QProcess::readyReadStandardError, this,
            [this] { readChannel(QProcess::StandardError); });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        readChannel(QProcess::StandardOutput);
        readChannel(QProcess::StandardError);
        if (status == QProcess::CrashExit)
            done(1, tr("The program stopped unexpectedly"));
        // pkexec's own codes: no rule matched and no agent could ask.
        else if (m_root && (code == 126 || code == 127))
            done(code, tr("Not authorised: no polkit rule allows this program"));
        else
            done(code, QString());
    });
    connect(m_proc, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e == QProcess::FailedToStart)
            done(1, m_proc->errorString());
    });

    QStringList args = argv;
    QString program = args.takeFirst();
    if (root) {
        args.prepend(program);
        program = QStringLiteral("/usr/bin/pkexec");
    }
    m_proc->start(program, args);
    // A CLI that watches stdin treats EOF as cancel, so only jobs that asked for input keep it.
    if (!options.value(QStringLiteral("input")).toBool())
        m_proc->closeWriteChannel();
    emit runningChanged();
    return true;
}

void Job::send(const QString &line)
{
    if (m_proc)
        m_proc->write((line + u'\n').toUtf8());
}

void Job::closeInput()
{
    if (m_proc)
        m_proc->closeWriteChannel();
}

void Job::readChannel(QProcess::ProcessChannel channel)
{
    if (!m_proc)
        return;
    const bool out = channel == QProcess::StandardOutput;
    QByteArray &buf = m_partial[out ? 0 : 1];
    buf += out ? m_proc->readAllStandardOutput() : m_proc->readAllStandardError();
    qsizetype nl;
    while ((nl = buf.indexOf('\n')) >= 0) {
        QByteArray l = buf.left(nl);
        buf.remove(0, nl + 1);
        if (l.endsWith('\r'))
            l.chop(1);
        handleLine(QString::fromUtf8(l), out);
    }
}

void Job::handleLine(const QString &text, bool fromStdout)
{
    if (fromStdout && text.startsWith(kMark)) {
        const QJsonDocument doc = QJsonDocument::fromJson(text.mid(kMark.size()).toUtf8());
        if (doc.isObject()) {
            const QVariantMap data = doc.object().toVariantMap();
            if (data.contains(QStringLiteral("phase")))
                m_phase = data.value(QStringLiteral("phase")).toString();
            if (data.contains(QStringLiteral("text")))
                m_text = data.value(QStringLiteral("text")).toString();
            if (data.contains(QStringLiteral("progress"))) {
                bool ok = false;
                const qreal p = data.value(QStringLiteral("progress")).toReal(&ok);
                m_progress = ok ? qBound(0.0, p, 1.0) : -1;
            }
            emit progressChanged();
            emit event(data);
            return;
        }
    }
    if (fromStdout)
        m_output += text + u'\n';
    if (!text.trimmed().isEmpty()) {
        m_tail.append(text);
        if (m_tail.size() > kTailLines)
            m_tail.removeFirst();
    }
    emit line(text);
}

void Job::done(int exitCode, const QString &error)
{
    if (!m_proc)
        return;
    for (int i : {0, 1}) {
        if (!m_partial[i].isEmpty())
            handleLine(QString::fromUtf8(m_partial[i]), i == 0);
        m_partial[i].clear();
    }
    m_proc->deleteLater();
    m_proc = nullptr;
    m_exitCode = exitCode;
    if (exitCode == 0)
        m_error.clear();
    else if (!error.isEmpty())
        m_error = error;
    else if (!m_tail.isEmpty())
        m_error = m_tail.join(u'\n');
    else
        m_error = tr("Failed (exit code %1)").arg(exitCode);
    emit runningChanged();
    emit finished(exitCode);
}
