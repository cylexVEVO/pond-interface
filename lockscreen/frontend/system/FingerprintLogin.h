#pragma once

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QFile>
#include <QFileInfo>
#include <QFileSystemWatcher>
#include <QObject>
#include <QtQml/qqmlregistration.h>

// An empty SDDM login also reaches password PAM. Only arm it when fingerprint
// PAM is configured and this user has an enrolled finger on a connected reader.
class FingerprintLogin : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString userName READ userName WRITE setUserName NOTIFY userNameChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit FingerprintLogin(QObject *parent = nullptr)
        : FingerprintLogin(QDBusConnection::systemBus(), QStringLiteral("/etc/pam.d/sddm"), parent) {}

    FingerprintLogin(QDBusConnection bus, QString pamPath, QObject *parent = nullptr)
        : QObject(parent), m_bus(bus), m_pamPath(pamPath), m_watcher(this) {
        m_watcher.addPath(QFileInfo(m_pamPath).absolutePath());
        connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &FingerprintLogin::refresh);
        connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &FingerprintLogin::refresh);
    }

    QString userName() const { return m_userName; }
    bool ready() const { return m_ready; }
    bool available() const { return m_available; }
    void setUserName(const QString &name) {
        if (m_userName == name)
            return;
        m_userName = name;
        emit userNameChanged();
        refresh();
    }

signals:
    void userNameChanged();
    void readyChanged();
    void availableChanged();

private:
    void setReady(bool ready) {
        if (m_ready == ready)
            return;
        m_ready = ready;
        emit readyChanged();
    }

    void setAvailable(bool available) {
        if (m_available == available)
            return;
        m_available = available;
        emit availableChanged();
    }

    void refresh() {
        const auto generation = ++m_generation;
        setReady(false);
        setAvailable(false);
        if (!m_watcher.files().contains(m_pamPath))
            m_watcher.addPath(m_pamPath);
        QFile pam(m_pamPath);
        if (m_userName.isEmpty() || !pam.open(QIODevice::ReadOnly))
            return;
        bool configured = false;
        for (const auto &line : pam.readAll().split('\n')) {
            const auto rule = line.split('#').first().simplified();
            configured |= (rule.startsWith("auth ") || rule.startsWith("-auth "))
                && rule.split(' ').contains("pam_fprintd.so");
        }
        if (!configured)
            return;

        auto request = QDBusMessage::createMethodCall(QStringLiteral("net.reactivated.Fprint"),
            QStringLiteral("/net/reactivated/Fprint/Manager"),
            QStringLiteral("net.reactivated.Fprint.Manager"), QStringLiteral("GetDefaultDevice"));
        auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(request, 3000), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, generation](auto *call) {
            QDBusPendingReply<QDBusObjectPath> reply = *call;
            call->deleteLater();
            if (generation != m_generation || reply.isError())
                return;
            auto request = QDBusMessage::createMethodCall(QStringLiteral("net.reactivated.Fprint"),
                reply.value().path(), QStringLiteral("net.reactivated.Fprint.Device"),
                QStringLiteral("ListEnrolledFingers"));
            request << m_userName;
            auto *watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(request, 3000), this);
            connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, generation](auto *call) {
                QDBusPendingReply<QStringList> reply = *call;
                call->deleteLater();
                if (generation != m_generation)
                    return;
                const bool enrolled = !reply.isError() && !reply.value().isEmpty();
                // The default fprintd policy prevents SDDM's unprivileged greeter
                // from listing another user's prints. Offer an explicit scan in
                // that case; never weaken the policy or submit unattended PAM.
                setAvailable(enrolled || reply.error().name()
                    == QStringLiteral("net.reactivated.Fprint.Error.PermissionDenied"));
                setReady(enrolled);
            });
        });
    }

    QDBusConnection m_bus;
    QString m_pamPath;
    QFileSystemWatcher m_watcher;
    QString m_userName;
    quint64 m_generation = 0;
    bool m_ready = false;
    bool m_available = false;
};
