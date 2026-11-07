#include "FingerprintLogin.h"
#include <QDBusContext>
#include <QTemporaryDir>
#include <QtTest>

class Reader : public QObject {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "net.reactivated.Fprint.Device")
public:
    QMap<QString, QStringList> fingers;
public slots:
    QStringList ListEnrolledFingers(const QString &user) { return fingers.value(user); }
};

class Manager : public QObject, protected QDBusContext {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "net.reactivated.Fprint.Manager")
public:
    bool connected = false;
    int queries = 0;
public slots:
    QDBusObjectPath GetDefaultDevice() {
        ++queries;
        if (!connected)
            sendErrorReply("net.reactivated.Fprint.Error.NoSuchDevice", "No reader");
        return QDBusObjectPath("/net/reactivated/Fprint/Device/0");
    }
};

class FingerprintLoginTest : public QObject {
    Q_OBJECT
    QTemporaryDir directory;
    Manager manager;
    Reader reader;
    QDBusConnection bus = QDBusConnection::sessionBus();
    QString pamPath() const { return directory.filePath("sddm"); }
    void configure(const QByteArray &contents = "auth sufficient pam_fprintd.so\n") {
        QFile file(pamPath());
        QVERIFY(file.open(QIODevice::WriteOnly));
        file.write(contents);
    }
private slots:
    void initTestCase() {
        QVERIFY(bus.registerService("net.reactivated.Fprint"));
        QVERIFY(bus.registerObject("/net/reactivated/Fprint/Manager", &manager, QDBusConnection::ExportAllSlots));
        QVERIFY(bus.registerObject("/net/reactivated/Fprint/Device/0", &reader, QDBusConnection::ExportAllSlots));
    }
    void init() {
        manager.connected = false;
        manager.queries = 0;
        reader.fingers.clear();
    }
    void passwordOnlyPamNeverProbes() {
        configure("# auth sufficient pam_fprintd.so\nauth include system-login\n");
        FingerprintLogin status(bus, pamPath());
        status.setUserName("alice");
        QTest::qWait(100);
        QVERIFY(!status.ready());
        QCOMPARE(manager.queries, 0);
    }
    void noReaderDoesNotArmLogin() {
        configure();
        FingerprintLogin status(bus, pamPath());
        status.setUserName("alice");
        QTRY_COMPARE(manager.queries, 1);
        QTest::qWait(50);
        QVERIFY(!status.ready());
    }
    void noEnrollmentDoesNotArmLogin() {
        configure();
        manager.connected = true;
        FingerprintLogin status(bus, pamPath());
        status.setUserName("alice");
        QTRY_COMPARE(manager.queries, 1);
        QTest::qWait(50);
        QVERIFY(!status.ready());
    }
    void enrolledUserCanArmLogin() {
        configure();
        manager.connected = true;
        reader.fingers["alice"] = {"right-index-finger"};
        FingerprintLogin status(bus, pamPath());
        status.setUserName("alice");
        QTRY_VERIFY(status.ready());
        status.setUserName("bob");
        QVERIFY(!status.ready());
        QTRY_COMPARE(manager.queries, 2);
        QTest::qWait(50);
        QVERIFY(!status.ready());
    }
    void staleUserReplyCannotArmLogin() {
        configure();
        manager.connected = true;
        reader.fingers["alice"] = {"right-index-finger"};
        FingerprintLogin status(bus, pamPath());
        status.setUserName("alice");
        status.setUserName("bob");
        QTRY_COMPARE(manager.queries, 2);
        QTest::qWait(50);
        QVERIFY(!status.ready());
    }
    void disabledPamDisarmsLogin() {
        configure();
        manager.connected = true;
        reader.fingers["alice"] = {"right-index-finger"};
        FingerprintLogin status(bus, pamPath());
        status.setUserName("alice");
        QTRY_VERIFY(status.ready());
        configure("auth include system-login\n");
        QTRY_VERIFY(!status.ready());
    }
};
QTEST_GUILESS_MAIN(FingerprintLoginTest)
#include "fingerprint-login.moc"
