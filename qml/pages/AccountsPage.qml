import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var rows: []
    property var shown: []

    function applyFilters() {
        var q = searchUsers.text.trim().toLowerCase()
        var role = roleFilter.currentIndex === 0 ? "" : roleFilter.currentText
        var st = statusFilter.currentIndex
        shown = rows.filter(function(u) {
            if (role !== "" && u.role !== role) return false
            if (st === 1 && u.status !== "active") return false
            if (st === 2 && u.status === "active") return false
            if (q !== "" && (u.name + " " + u.email).toLowerCase().indexOf(q) < 0) return false
            return true
        })
    }
    function refresh() {
        rows = school.users()
        applyFilters()
    }
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { root.refresh() } }

    ColumnLayout {
        anchors.fill: parent
        spacing: 15

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Comptes & sécurité"; font.pixelSize: 28; font.bold: true }
            Item { Layout.fillWidth: true }
            AppButton { text: "Créer un compte"; onClicked: create.open() }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            AppTextField {
                id: searchUsers
                placeholderText: "Rechercher nom ou e-mail"
                Layout.fillWidth: true
                onTextChanged: root.applyFilters()
            }
            ComboBox {
                id: roleFilter
                Layout.preferredWidth: 180
                model: ["Tous les rôles"].concat(school.roles())
                onCurrentIndexChanged: root.applyFilters()
            }
            ComboBox {
                id: statusFilter
                Layout.preferredWidth: 160
                model: ["Tous les statuts", "Actifs", "Bloqués"]
                onCurrentIndexChanged: root.applyFilters()
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            model: root.shown
            delegate: Rectangle {
                width: parent.width
                height: 65
                color: index % 2 ? "#FAFBFC" : "white"
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 25
                    Label { text: modelData.name; width: 180; elide: Text.ElideRight }
                    Label { text: modelData.email; width: 220; elide: Text.ElideRight }
                    Label { text: modelData.role; width: 130 }
                    Label { text: modelData.status; width: 100 }
                    Label { text: modelData.blockedReason; width: 250; elide: Text.ElideRight }
                    AppButton {
                        text: "Bloquer"
                        enabled: modelData.status === "active"
                        onClicked: school.blockUser(modelData.id, "administratif", "Blocage administratif")
                    }
                    AppButton {
                        text: "Débloquer"
                        enabled: modelData.status !== "active"
                        onClicked: school.unblockUser(modelData.id)
                    }
                }
            }
        }
    }

    Dialog {
        id: create
        title: "Créer un compte"
        modal: true
        anchors.centerIn: Overlay.overlay
        standardButtons: Dialog.Ok | Dialog.Cancel
        Column {
            spacing: 8
            width: 400
            AppTextField { id: name; placeholderText: "Nom" }
            AppTextField { id: email; placeholderText: "E-mail" }
            AppTextField { id: password; placeholderText: "Mot de passe"; echoMode: TextInput.Password }
            ComboBox { id: role; model: school.roles() }
        }
        onAccepted: school.createUser({name: name.text, email: email.text, password: password.text, role: role.currentText})
    }
}
