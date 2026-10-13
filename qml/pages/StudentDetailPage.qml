import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    property int studentId: 0
    signal back()

    property var info: ({})
    property var guardianRows: []
    property var parentRows: []
    property var paymentRows: []

    function fmt(n) {
        return Math.round(Number(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ") + " Ar"
    }
    function refresh() {
        info = school.student(studentId)
        guardianRows = school.guardians(studentId)
        parentRows = school.parentLinks(studentId)
        paymentRows = school.payments(studentId)
    }
    onStudentIdChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }

    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Fiche élève"; font.pixelSize: 28; font.bold: true }
                Item { Layout.fillWidth: true }
                AppButton { text: "← Retour"; onClicked: back() }
                AppButton { text: "🖨 Liste"; onClicked: printer.printStudentList(info.className) }
                AppButton { text: "🪪 Carte élève"; onClicked: printer.printStudentCard(studentId) }
                AppButton { text: "🖨 Certificat"; onClicked: printer.printStudentCertificate(studentId) }
                AppButton { text: "🧾 Demande de paiement"; onClicked: printer.printPaymentRequest(studentId) }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: infoColumn.implicitHeight + 50

                Column {
                    id: infoColumn
                    x: 25; y: 25
                    width: parent.width - 50
                    spacing: 12
                    Label{text:info.firstName+" "+info.lastName; font.pixelSize:28;font.bold:true;color:"#0B2A43"}
                    Label{text:"Matricule : "+info.matricule}
                    Label{text:"Classe : "+info.className}
                    Label{text:"Date d'entrée : "+info.entryDate}
                    Label{text:"Date de naissance : "+info.birthDate+" — "+info.birthPlace}
                    Label{text:"Téléphone parent : "+info.parentPhone}
                    Label{text:"E-mail parent : "+info.parentEmail}
                    Label{text:"Adresse : "+info.address}
                    Label{text:"Ancienne école : "+info.previousSchool}
                    Label{text:"Projet : "+info.desiredCareer}
                    Label{text:"Paiements manqués consécutifs : "+info.missedPayments}
                    Label{text:"Statut du compte : "+info.accountStatus}
                    Row {
                        spacing: 8
                        AppButton{text:"Diplômé";onClicked:school.graduateStudent(studentId)}
                        AppButton{text:"Bloquer";onClicked:school.blockStudent(studentId,"Blocage administratif")}
                        AppButton{text:"Débloquer";onClicked:school.unblockStudent(studentId)}
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: guardianColumn.implicitHeight + 40

                ColumnLayout {
                    id: guardianColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Parents et tuteurs";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Repeater {
                        model: guardianRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: (modelData.isPrimary ? "★ " : "") + modelData.fullName + " — " + modelData.relation
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            Label{text:modelData.phone; color:"#667085"}
                            AppButton{text:"Retirer"; onClicked: school.removeGuardian(modelData.linkId)}
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        AppTextField{id:gName; placeholderText:"Nom complet"; Layout.fillWidth:true}
                        AppTextField{id:gRelation; placeholderText:"Lien (père, mère…)"; Layout.preferredWidth:160}
                        AppTextField{id:gPhone; placeholderText:"Téléphone"; Layout.preferredWidth:140}
                        CheckBox{id:gPrimary; text:"Principal"}
                        AppButton{
                            text:"Ajouter"; highlighted:true
                            onClicked: {
                                if (school.addGuardian(studentId, {fullName:gName.text, relation:gRelation.text, phone:gPhone.text, isPrimary:gPrimary.checked})) {
                                    gName.text=""; gRelation.text=""; gPhone.text=""; gPrimary.checked=false
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: parentColumn.implicitHeight + 40

                ColumnLayout {
                    id: parentColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Accès famille (compte parent)";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Label {
                        text: "Créez le compte parent dans Comptes / sécurité, puis rattachez-le ici par son adresse e-mail."
                        color: "#667085"; wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Repeater {
                        model: parentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: modelData.name + " — " + modelData.email
                                Layout.fillWidth: true; elide: Text.ElideRight
                            }
                            AppButton{text:"Retirer l'accès"; onClicked: school.unlinkParent(modelData.linkId)}
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        AppTextField{id:parentEmail; placeholderText:"E-mail du compte parent"; Layout.fillWidth:true}
                        AppButton{
                            text:"Lier le compte"; highlighted:true
                            onClicked: { if (school.linkParentByEmail(studentId, parentEmail.text)) parentEmail.text = "" }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: 16
                color: "white"
                implicitHeight: paymentColumn.implicitHeight + 40

                ColumnLayout {
                    id: paymentColumn
                    x: 20; y: 20
                    width: parent.width - 40
                    spacing: 10

                    Label{text:"Paiements";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                    Label {
                        visible: paymentRows.length === 0
                        text: "Aucun paiement enregistré pour cet élève."
                        color: "#667085"
                    }
                    Repeater {
                        model: paymentRows
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Label{text:modelData.paidAt; Layout.preferredWidth: 170}
                            Label{text:modelData.method; color:"#667085"; Layout.fillWidth: true}
                            Label{text:fmt(modelData.amount); font.bold:true}
                            AppButton{text:"🧾 Reçu"; onClicked: printer.printReceipt(modelData.id)}
                        }
                    }
                }
            }
        }
    }
}
