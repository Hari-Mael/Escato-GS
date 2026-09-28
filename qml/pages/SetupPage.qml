import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Affiché uniquement tant qu'aucun administrateur n'existe (premier lancement).
Rectangle {
    color: "#EEF4F8"

    Rectangle {
        width: 460; height: 590
        anchors.centerIn: parent
        radius: 22
        color: "white"
        border.color: "#E1E8EF"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 38
            spacing: 14

            Label { text: "ESCATO"; font.pixelSize: 30; font.bold: true; color: "#0B2A43"; Layout.alignment: Qt.AlignHCenter }
            Label { text: "Première configuration"; font.pixelSize: 18; font.bold: true; Layout.alignment: Qt.AlignHCenter }
            Label {
                text: "Créez le compte administrateur. Il aura le contrôle complet de l'application et pourra ensuite créer tous les autres comptes."
                color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
            }

            TextField { id: fullName; Layout.fillWidth: true; placeholderText: "Nom complet" }
            TextField { id: adminEmail; Layout.fillWidth: true; placeholderText: "Adresse e-mail"; inputMethodHints: Qt.ImhEmailCharactersOnly }
            TextField { id: pwd; Layout.fillWidth: true; placeholderText: "Mot de passe (8 caractères minimum)"; echoMode: TextInput.Password }
            TextField { id: pwd2; Layout.fillWidth: true; placeholderText: "Confirmer le mot de passe"; echoMode: TextInput.Password; onAccepted: submit() }

            Button {
                Layout.fillWidth: true
                text: "Créer le compte administrateur"
                highlighted: true
                onClicked: submit()
            }

            Label { id: error; color: "#C62828"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap }
            Item { Layout.fillHeight: true }
        }
    }

    function submit() {
        error.text = ""
        if (!fullName.text.trim() || !adminEmail.text.trim()) { error.text = "Le nom et l'adresse e-mail sont obligatoires."; return }
        if (pwd.text.length < 8) { error.text = "Le mot de passe doit contenir au moins 8 caractères."; return }
        if (pwd.text !== pwd2.text) { error.text = "Les deux mots de passe ne correspondent pas."; return }
        // En cas de succès, la session s'ouvre automatiquement et Main.qml affiche l'application.
        school.createFirstAdmin(fullName.text, adminEmail.text, pwd.text)
    }
}
