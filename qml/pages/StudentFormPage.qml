import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    signal saved()
    property int editingId: 0
    onEditingIdChanged: photoPicker.path = editingId ? school.studentPhotoPath(editingId) : ""

    ColumnLayout {
        anchors.fill: parent; spacing: 16
        RowLayout {
            Label { text: editingId ? "Modifier l'élève" : "Inscrire un élève"; font.pixelSize:28; font.bold:true }
            Item { Layout.fillWidth:true }
            AppButton { text:"← Retour"; onClicked:saved() }
        }

        ScrollView {
            Layout.fillWidth:true; Layout.fillHeight:true
            GridLayout {
                PhotoPicker { id: photoPicker; Layout.columnSpan: 2 }
                width: parent.width; columns:2; columnSpacing:20; rowSpacing:14

                Label{text:"Matricule"} AppTextField{id: matricule; placeholderText:"Laisser vide pour génération automatique"; Layout.fillWidth:true}
                Label{text:"Nom *"} AppTextField{id: lastName; Layout.fillWidth:true}
                Label{text:"Prénom *"} AppTextField{id: firstName; Layout.fillWidth:true}
                Label{text:"Date de naissance *"} AppTextField{id: birthDate; placeholderText:"AAAA-MM-JJ"; Layout.fillWidth:true}
                Label{text:"Lieu de naissance"} AppTextField{id: birthPlace; Layout.fillWidth:true}
                Label{text:"Père"} AppTextField{id: father; Layout.fillWidth:true}
                Label{text:"Profession du père"} AppTextField{id: fatherJob; Layout.fillWidth:true}
                Label{text:"Mère"} AppTextField{id: mother; Layout.fillWidth:true}
                Label{text:"Profession de la mère"} AppTextField{id: motherJob; Layout.fillWidth:true}
                Label{text:"Téléphone parent *"} AppTextField{id: parentPhone; Layout.fillWidth:true}
                Label{text:"E-mail parent"} AppTextField{id: parentEmail; Layout.fillWidth:true}
                Label{text:"Adresse *"} AppTextField{id: address; Layout.fillWidth:true}
                Label{text:"Ancienne école"} AppTextField{id: previousSchool; Layout.fillWidth:true}
                Label{text:"Ancienne classe"} AppTextField{id: previousClass; Layout.fillWidth:true}
                Label{text:"Date d'entrée *"} AppTextField{id: entryDate; placeholderText:"AAAA-MM-JJ"; Layout.fillWidth:true}
                Label{text:"Classe actuelle *"}
                ComboBox { id: classBox; model:school.classes(); Layout.fillWidth:true }
                Label{text:"Projet / carrière"} AppTextField{id: career; Layout.fillWidth:true}

                Label { id: formError; Layout.columnSpan:2; color:"#C62828"; visible: text !== "" }

                AppButton {
                    Layout.columnSpan:2; Layout.alignment:Qt.AlignRight
                    text:editingId?"Enregistrer les modifications":"Enregistrer l'élève"
                    highlighted:true
                    onClicked: save()
                }
            }
        }
    }

    function formData() {
        return {
            lastName:lastName.text, firstName:firstName.text, birthDate:birthDate.text,
            birthPlace:birthPlace.text, fatherName:father.text, fatherJob:fatherJob.text,
            motherName:mother.text, motherJob:motherJob.text, parentPhone:parentPhone.text,
            parentEmail:parentEmail.text, address:address.text, previousSchool:previousSchool.text,
            previousClass:previousClass.text, className:classBox.currentText,
            desiredCareer:career.text, photo:photoPicker.path, entryDate:entryDate.text,
            matricule:matricule.text.trim()
        }
    }

    function save() {
        formError.text = ""
        if (!lastName.text || !firstName.text || !birthDate.text || !parentPhone.text || !address.text || !entryDate.text || classBox.currentIndex < 0) {
            formError.text = "Merci de remplir tous les champs marqués d'un *."
            return
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(birthDate.text)) {
            formError.text = "La date de naissance doit être au format AAAA-MM-JJ."
            return
        }
        if (!/^\d{4}-\d{2}-\d{2}$/.test(entryDate.text)) {
            formError.text = "La date d'entrée doit être au format AAAA-MM-JJ."
            return
        }
        var ok = editingId ? school.updateStudent(editingId,formData()) : school.addStudent(formData())
        if(ok) { reset(); saved() }
    }

    function reset() {
        photoPicker.path = ""
        [matricule, lastName, firstName, birthDate, birthPlace, father, fatherJob, mother, motherJob,
         parentPhone, parentEmail, address, previousSchool, previousClass, entryDate, career].forEach(function(f){ f.text = "" })
        classBox.currentIndex = 0
        formError.text = ""
    }
}
