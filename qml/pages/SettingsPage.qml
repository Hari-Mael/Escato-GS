import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property var periods: []
    property bool canSettings: false
    property bool canPeriods: false

    function refreshPerms() {
        canSettings = school.can("settings.manage")
        canPeriods = school.can("periods.manage")
    }

    function refreshPeriods() {
        periods = school.academicPeriods()
    }
    Component.onCompleted: {
        schoolName.text = school.setting("school_name")
        schoolCity.text = school.setting("school_city")
        signatory.text = school.setting("signatory_title")
        refreshPerms()
        refreshPeriods()
        passMark.text = school.setting("pass_mark")
        retakeMark.text = school.setting("retake_mark")
    }
    Connections {
        target: school
        function onDataChanged() { root.refreshPerms(); root.refreshPeriods() }
        function onSessionChanged() { root.refreshPerms() }
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Paramètres"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: accountColumn.implicitHeight + 40

                ColumnLayout {
                    id: accountColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 8
                    Label { text: "Compte"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Nom : " + school.currentUser }
                    Label { text: "Rôle : " + school.currentRole }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: schoolColumn.implicitHeight + 40

                ColumnLayout {
                    id: schoolColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Label { text: "Établissement et documents officiels"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Ces informations apparaissent sur les reçus, attestations, certificats et demandes de paiement."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    AppTextField { id: schoolName; Layout.fillWidth: true; placeholderText: "Nom de l'établissement"; enabled: root.canSettings }
                    AppTextField { id: schoolCity; Layout.fillWidth: true; placeholderText: "Ville (ex. Tolagnaro)"; enabled: root.canSettings }
                    AppTextField { id: signatory; Layout.fillWidth: true; placeholderText: "Titre du signataire (ex. Le Frère Directeur)"; enabled: root.canSettings }
                    AppButton {
                        text: "Enregistrer"
                        highlighted: true
                        visible: root.canSettings
                        onClicked: {
                            school.setSetting("school_name", schoolName.text)
                            school.setSetting("school_city", schoolCity.text)
                            school.setSetting("signatory_title", signatory.text)
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: logoColumn.implicitHeight + 40
                ColumnLayout {
                    id: logoColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 10
                    Label { text: "Logo de l'établissement"; font.pixelSize: 18; font.bold: true }
                    Label { text: "Ce logo apparaît dans le menu latéral. Formats JPG ou PNG."; color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    PhotoPicker {
                        size: 120
                        path: school.setting("school_logo")
                        onPhotoChanged: function(p) { school.setSetting("school_logo", p) }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: thresholdColumn.implicitHeight + 40

                ColumnLayout {
                    id: thresholdColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Label { text: "Seuils de décision des délibérations"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Moyenne sur 20 : admis à partir du premier seuil, rattrapage à partir du second, ajourné en dessous."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Label { text: "Admis à partir de" }
                        AppTextField { id: passMark; Layout.preferredWidth: 110; enabled: root.canSettings; inputMethodHints: Qt.ImhDigitsOnly }
                        Label { text: "Rattrapage à partir de" }
                        AppTextField { id: retakeMark; Layout.preferredWidth: 110; enabled: root.canSettings; inputMethodHints: Qt.ImhDigitsOnly }
                        AppButton {
                            text: "Enregistrer"
                            highlighted: true
                            visible: root.canSettings
                            onClicked: {
                                school.setSetting("pass_mark", passMark.text.replace(",", "."))
                                school.setSetting("retake_mark", retakeMark.text.replace(",", "."))
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 12
                color: "white"
                border.color: "#E5EAEE"
                implicitHeight: periodColumn.implicitHeight + 40

                ColumnLayout {
                    id: periodColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10
                    Label { text: "Périodes académiques"; font.pixelSize: 18; font.bold: true }
                    Label { visible: root.periods.length === 0; text: "Aucune période enregistrée."; color: "#667085" }
                    Repeater {
                        model: root.periods
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: modelData.name + "  (" + modelData.startDate + " → " + modelData.endDate + ")"
                                font.bold: modelData.isActive
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Label { text: modelData.isActive ? "Active" : ""; color: "#0F9D8F"; font.bold: true }
                            AppButton {
                                text: "Activer"
                                visible: root.canPeriods && !modelData.isActive
                                onClicked: school.setActiveAcademicPeriod(modelData.id)
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.canPeriods
                        spacing: 8
                        AppTextField { id: periodName; placeholderText: "Ex. 2026 – 2027"; Layout.fillWidth: true }
                        AppTextField { id: periodStart; placeholderText: "Début JJ-MM-AAAA"; Layout.preferredWidth: 170 }
                        AppTextField { id: periodEnd; placeholderText: "Fin JJ-MM-AAAA"; Layout.preferredWidth: 170 }
                        AppButton {
                            text: "Ajouter"
                            highlighted: true
                            onClicked: {
                                if (school.addAcademicPeriod({name: periodName.text, startDate: periodStart.text, endDate: periodEnd.text})) {
                                    periodName.text = ""; periodStart.text = ""; periodEnd.text = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
