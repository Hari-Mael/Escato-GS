import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var cfg: ({})
    property var logRows: []
    property bool canConfig: false
    property bool canSend: false

    function refresh() {
        canConfig = school.can("email.config")
        canSend = school.can("email.send")
        cfg = school.smtpSettings()
        logRows = school.emailLog(200)
        if (cfg.host !== undefined) {
            hostField.text = cfg.host || ""
            portField.text = String(cfg.port || 587)
            userField.text = cfg.user || ""
            fromField.text = cfg.from || ""
            timeField.text = cfg.scheduleTime || "08:00"
            schedCheck.checked = !!cfg.scheduleEnabled
            securityBox.currentIndex = Math.max(0, ["starttls", "ssl", "none"].indexOf(cfg.security || "starttls"))
        }
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Rapports par e-mail"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                visible: root.canConfig
                implicitHeight: smtpColumn.implicitHeight + 40
                ColumnLayout {
                    id: smtpColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Serveur d'envoi (SMTP)"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Le mot de passe n'est jamais enregistré : saisissez-le à chaque session. Pour Gmail, utilisez un mot de passe d'application."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: hostField; placeholderText: "Serveur (ex. smtp.gmail.com)"; Layout.fillWidth: true }
                        AppTextField { id: portField; placeholderText: "Port"; Layout.preferredWidth: 90; inputMethodHints: Qt.ImhDigitsOnly }
                        ComboBox { id: securityBox; Layout.preferredWidth: 180; model: ["STARTTLS", "SSL", "Sans chiffrement"] }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: userField; placeholderText: "Identifiant (adresse e-mail)"; Layout.fillWidth: true }
                        AppTextField { id: fromField; placeholderText: "Adresse expéditrice"; Layout.fillWidth: true }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: passField; placeholderText: "Mot de passe (session uniquement)"; echoMode: TextInput.Password; Layout.fillWidth: true }
                        AppButton { text: "Mémoriser pour cette session"; onClicked: { school.setSmtpPassword(passField.text); passField.text = "" } }
                    }
                    AppButton {
                        text: "Enregistrer le serveur"; highlighted: true
                        onClicked: school.saveSmtpSettings({host: hostField.text, port: parseInt(portField.text) || 587, user: userField.text,
                                                            from: fromField.text, security: ["starttls", "ssl", "none"][securityBox.currentIndex]})
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                visible: root.canSend
                implicitHeight: sendColumn.implicitHeight + 40
                ColumnLayout {
                    id: sendColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Envois"; font.pixelSize: 18; font.bold: true }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppTextField { id: testTo; placeholderText: "Adresse de test"; Layout.fillWidth: true }
                        AppButton { text: "Envoyer un test"; visible: root.canConfig; onClicked: school.sendTestEmail(testTo.text) }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppButton { text: "Relancer les parents (impayés)"; highlighted: true; onClicked: school.sendOverdueReminders() }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        CheckBox { id: schedCheck; text: "Relances automatiques chaque jour à" }
                        AppTextField { id: timeField; Layout.preferredWidth: 90; placeholderText: "HH:mm" }
                        AppButton {
                            text: "Enregistrer la planification"; visible: root.canConfig
                            onClicked: school.saveEmailSchedule(schedCheck.checked, timeField.text)
                        }
                    }
                    Label {
                        text: "La planification ne fonctionne que si l'application est ouverte et qu'une session est active à l'heure prévue."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                visible: root.canSend
                implicitHeight: logColumn.implicitHeight + 40
                ColumnLayout {
                    id: logColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 6
                    Label { text: "Historique des envois"; font.pixelSize: 18; font.bold: true }
                    Repeater {
                        model: root.logRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label { text: modelData.createdAt; Layout.preferredWidth: 150; color: "#667085" }
                            Label { text: modelData.recipient; Layout.preferredWidth: 220; elide: Text.ElideRight }
                            Label { text: modelData.subject; Layout.fillWidth: true; elide: Text.ElideRight }
                            Label { text: modelData.status; font.bold: true; color: modelData.status === "envoyé" ? "#0F9D8F" : "#C62828" }
                        }
                    }
                }
            }
        }
    }
}
