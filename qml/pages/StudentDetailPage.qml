import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    property int studentId: 0
    signal back()

    ColumnLayout {
        anchors.fill: parent; spacing:16
        RowLayout {
            Label{text:"Fiche élève";font.pixelSize:28;font.bold:true}
            Item{Layout.fillWidth:true}
            AppButton{text:"← Retour";onClicked:back()}
            AppButton{text:"🖨 Imprimer la liste";onClicked:printer.printStudentList(info.className)}
            AppButton{text:"🪪 Carte élève";onClicked:printer.printStudentCard(studentId)}
            AppButton{text:"🖨 Certificat de scolarité";onClicked:printer.printStudentCertificate(studentId)}
        }
        Rectangle {
            Layout.fillWidth:true; Layout.fillHeight:true; radius:16; color:"white"
            Column {
                anchors.fill:parent; anchors.margins:25; spacing:12
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
                    spacing:8
                    AppButton{text:"Diplômé";onClicked:school.graduateStudent(studentId)}
                    AppButton{text:"Bloquer";onClicked:school.blockStudent(studentId,"Blocage administratif")}
                    AppButton{text:"Débloquer";onClicked:school.unblockStudent(studentId)}
                }
            }
        }
        Rectangle {
            Layout.fillWidth:true; Layout.preferredHeight:300; radius:16; color:"white"
            ColumnLayout {
                anchors.fill:parent; anchors.margins:20; spacing:10
                Label{text:"Parents et tuteurs";font.pixelSize:20;font.bold:true;color:"#0B2A43"}
                ListView {
                    Layout.fillWidth:true; Layout.fillHeight:true; clip:true
                    model: guardianRows
                    delegate: RowLayout {
                        width: ListView.view.width
                        Label {
                            text: (modelData.isPrimary ? "★ " : "") + modelData.fullName + " — " + modelData.relation
                            Layout.fillWidth:true; elide: Text.ElideRight
                        }
                        Label{text:modelData.phone; color:"#667085"}
                        AppButton{text:"Retirer"; onClicked: school.removeGuardian(modelData.linkId)}
                    }
                }
                RowLayout {
                    Layout.fillWidth:true; spacing:8
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
    }
    property var info: ({})
    property var guardianRows: []
    onStudentIdChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }
    function refresh() {
        info = school.student(studentId)
        guardianRows = school.guardians(studentId)
    }
}
