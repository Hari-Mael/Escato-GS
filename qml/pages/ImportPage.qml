import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import "../components"

Item {
    id: root
    property var result: ({})
    readonly property string template: school.studentsCsvTemplate()

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 18

            Label { text: "Importation des données"; font.pixelSize: 28; font.bold: true }

            Rectangle {
                Layout.fillWidth: true; radius: 12; color: "white"; border.color: "#E5EAEE"
                implicitHeight: helpColumn.implicitHeight + 40
                ColumnLayout {
                    id: helpColumn
                    x: 20; y: 20; width: parent.width - 40; spacing: 8
                    Label { text: "Importer des élèves"; font.pixelSize: 18; font.bold: true }
                    Label {
                        text: "Copiez vos élèves depuis un tableur (Excel, LibreOffice) et collez-les ci-dessous, en gardant la première ligne d'en-tête. Colonnes obligatoires : nom, prenom, date_naissance (JJ-MM-AAAA), classe, telephone_parent, adresse. Colonnes facultatives : lieu_naissance, email_parent."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Label { text: "Modèle d'en-tête :"; font.bold: true }
                    TextField {
                        Layout.fillWidth: true
                        readOnly: true
                        selectByMouse: true
                        text: root.template
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        Label { text: "Type :" }
                        ComboBox { id: importType; Layout.preferredWidth: 200; model: ["Élèves", "Enseignants"] }
                        AppButton { text: "Choisir un fichier CSV…"; onClicked: fileDialog.open() }
                        Label {
                            text: "Excel : Enregistrer sous → CSV (séparateur ;). Access : exporter la table en CSV."
                            color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                        }
                    }
                    FileDialog {
                        id: fileDialog
                        nameFilters: ["Fichiers CSV (*.csv *.txt)"]
                        onAccepted: csvInput.text = school.readTextFile(selectedFile.toString())
                    }
                    Label { text: "Données à importer :"; font.bold: true }
                    TextArea {
                        id: csvInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        placeholderText: root.template + "Rakoto;Jean;2014-03-04;Tolagnaro;CM2;0340000000;parent@mail.mg;Toamasina"
                        wrapMode: TextArea.NoWrap
                        selectByMouse: true
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 8
                        AppButton {
                            text: "Importer les élèves"; highlighted: true
                            onClicked: root.result = importType.currentIndex === 0 ? school.importStudentsCsv(csvInput.text) : school.importTeachersCsv(csvInput.text)
                        }
                        AppButton { text: "Vider"; onClicked: { csvInput.text = ""; root.result = ({}) } }
                        Item { Layout.fillWidth: true }
                    }
                    Label {
                        visible: root.result.imported !== undefined
                        text: (importType.currentIndex === 0 ? "Élèves importés : " : "Enseignants importés : ") + (root.result.imported || 0) + "   ·   Lignes refusées : " + (root.result.rejected || 0)
                        font.bold: true
                        color: (root.result.rejected || 0) === 0 ? "#0F9D8F" : "#B7791F"
                    }
                    Repeater {
                        model: root.result.errors || []
                        delegate: Label { text: modelData; color: "#C62828"; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                    }
                }
            }
        }
    }
}
