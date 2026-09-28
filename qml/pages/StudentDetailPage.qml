import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    property int studentId: 0
    signal back()

    ColumnLayout {
        anchors.fill: parent; spacing:16
        RowLayout {
            Label{text:"Fiche élève";font.pixelSize:28;font.bold:true}
            Item{Layout.fillWidth:true}
            Button{text:"← Retour";onClicked:back()}
            Button{text:"🖨 Imprimer la liste";onClicked:printer.printStudentList(info.className)}
        }
        Rectangle {
            Layout.fillWidth:true; Layout.fillHeight:true; radius:16; color:"white"
            Column {
                anchors.fill:parent; anchors.margins:25; spacing:12
                Label{text:info.firstName+" "+info.lastName; font.pixelSize:28;font.bold:true;color:"#0B2A43"}
                Label{text:"Matricule : "+info.matricule}
                Label{text:"Classe : "+info.className}
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
                    Button{text:"Diplômé";onClicked:school.graduateStudent(studentId)}
                    Button{text:"Bloquer";onClicked:school.blockStudent(studentId,"Blocage administratif")}
                    Button{text:"Débloquer";onClicked:school.unblockStudent(studentId)}
                }
            }
        }
    }
    property var info: ({})
    onStudentIdChanged: refresh()
    Component.onCompleted: refresh()
    Connections { target: school; function onDataChanged() { refresh() } }
    function refresh() { info = school.student(studentId) }
}
