import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    color: "#EEF4F8"
    signal success()

    Rectangle {
        width: 420; height: 400
        anchors.centerIn: parent
        radius: 22
        color: "white"
        border.color: "#E1E8EF"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 38
            spacing: 18

            Label { text: "ESCATO"; font.pixelSize: 30; font.bold: true; color: "#0B2A43"; Layout.alignment: Qt.AlignHCenter }
            Label { text: "Accédez à votre espace de travail"; color: "#667085"; Layout.alignment: Qt.AlignHCenter }

            TextField { id: email; Layout.fillWidth: true; placeholderText: "Adresse e-mail" }
            TextField { id: password; Layout.fillWidth: true; placeholderText: "Mot de passe"; echoMode: TextInput.Password; onAccepted: doLogin() }

            Button {
                Layout.fillWidth: true
                text: "Se connecter"
                highlighted: true
                onClicked: doLogin()
            }

            Label { id: error; color: "#C62828"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap }
        }
    }

    function doLogin() {
        error.text = ""
        if (school.login(email.text, password.text)) success()
        else error.text = "Identifiants incorrects ou compte bloqué."
    }
}
