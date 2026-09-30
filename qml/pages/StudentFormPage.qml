import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    signal saved()
    property int editingId: 0

    ColumnLayout {
        anchors.fill: parent; spacing: 16
        RowLayout {
            Label { text: editingId ? "Modifier l'élève" : "Inscrire un élève"; font.pixelSize:28; font.bold:true }
            Item { Layout.fillWidth:true }
            Button { text:"← Retour"; onClicked:saved() }
        }

        ScrollView {
            Layout.fillWidth:true; Layout.fillHeight:true
            GridLayout {
                width: parent.width; columns:2; columnSpacing:20; rowSpacing:14

                Label{text:"Matricule"} TextField{id: matricule; placeholderText:"Laisser vide pour génération automatique"; Layout.fillWidth:true}
                Label{text:"Nom *"} TextField{id: lastName; Layout.fillWidth:true}
                Label{text:"Prénom *"} TextField{id: firstName; Layout.fillWidth:true}
                Label{text:"Date de naissance *"} TextField{id: birthDate; placeholderText:"AAAA-MM-JJ"; Layout.fillWidth:true}
                Label{text:"Lieu de naissance"} TextField{id: birthPlace; Layout.fillWidth:true}
                Label{text:"Père"} TextField{id: father; Layout.fillWidth:true}
                Label{text:"Profession du père"} TextField{id: fatherJob; Layout.fillWidth:true}
                Label{text:"Mère"} TextField{id: mother; Layout.fillWidth:true}
                Label{text:"Profession de la mère"} TextField{id: motherJob; Layout.fillWidth:true}
                Label{text:"Téléphone parent *"} TextField{id: parentPhone; Layout.fillWidth:true}
                Label{text:"E-mail parent"} TextField{id: parentEmail; Layout.fillWidth:true}
                Label{text:"Adresse *"} TextField{id: address; Layout.fillWidth:true}
                Label{text:"Ancienne école"} TextField{id: previousSchool; Layout.fillWidth:true}
                Label{text:"Ancienne classe"} TextField{id: previousClass; Layout.fillWidth:true}
                Label{text:"Date d'entrée *"} TextField{id: entryDate; placeholderText:"AAAA-MM-JJ"; Layout.fillWidth:true}
                Label{text:"Classe actuelle *"}
                ComboBox { id: classBox; model:school.classes(); Layout.fillWidth:true }
                Label{text:"Projet / carrière"} TextField{id: career; Layout.fillWidth:true}

                Label { id: formError; Layout.columnSpan:2; color:"#C62828"; visible: text !== "" }

                Button {
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
            desiredCareer:career.text, photo:"", entryDate:entryDate.text,
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
        [matricule, lastName, firstName, birthDate, birthPlace, father, fatherJob, mother, motherJob,
         parentPhone, parentEmail, address, previousSchool, previousClass, entryDate, career].forEach(function(f){ f.text = "" })
        classBox.currentIndex = 0
        formError.text = ""
    }
}
