import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    signal saved()
    ColumnLayout{anchors.fill:parent;spacing:14
        RowLayout{Label{text:"Nouvel enseignant";font.pixelSize:28;font.bold:true}Item{Layout.fillWidth:true}Button{text:"← Retour";onClicked:saved()}}
        ScrollView{Layout.fillWidth:true;Layout.fillHeight:true
            GridLayout{width:parent.width;columns:2;columnSpacing:18;rowSpacing:12
                Label{text:"Nom *"}TextField{id:name;Layout.fillWidth:true}
                Label{text:"E-mail *"}TextField{id:email;Layout.fillWidth:true}
                Label{text:"Mot de passe * (8 car. min.)"}TextField{id:password;echoMode:TextInput.Password;Layout.fillWidth:true}
                Label{text:"CIN *"}TextField{id:cin;Layout.fillWidth:true}
                Label{text:"CNaPS"}TextField{id:cnaps;Layout.fillWidth:true}
                Label{text:"Matricule"}TextField{id:mle;Layout.fillWidth:true}
                Label{text:"Téléphone *"}TextField{id:contact;Layout.fillWidth:true}
                Label{text:"Adresse"}TextField{id:address;Layout.fillWidth:true}
                Label{text:"Date de naissance"}TextField{id:dob;Layout.fillWidth:true}
                Label{text:"Lieu de naissance"}TextField{id:birthPlace;Layout.fillWidth:true}
                Label{text:"Nombre d'enfants"}SpinBox{id:childCount;from:0;to:30;Layout.fillWidth:true}
                Label{text:"Situation familiale"}TextField{id:maritalStatus;Layout.fillWidth:true}
                Label{text:"Religion"}TextField{id:religion;Layout.fillWidth:true}
                Label{text:"Matière *"}TextField{id:subject;Layout.fillWidth:true}
                Label{text:"Fonction"}TextField{id:occupation;Layout.fillWidth:true}
                Label{text:"Type de contrat"}ComboBox{id:employmentType;model:["cdi","cdd"];Layout.fillWidth:true}
                Label{text:"Date d'embauche"}TextField{id:hiringDate;Layout.fillWidth:true}
                Label{text:"Fin de contrat"}TextField{id:contractEndDate;Layout.fillWidth:true}
                Label{text:"Commentaire"}TextArea{id:comment;Layout.fillWidth:true}
                Label{id:formError;Layout.columnSpan:2;color:"#C62828";visible:text!==""}
                Button{Layout.columnSpan:2;Layout.alignment:Qt.AlignRight;text:"Enregistrer";highlighted:true;onClicked:save()}
            }
        }
    }
    function save(){
        formError.text=""
        if(!name.text||!email.text||!cin.text||!contact.text||!subject.text||password.text.length<8){formError.text="Merci de remplir les champs marqués d'un * (mot de passe : 8 caractères minimum).";return}
        if(school.addTeacher(formData())){reset();saved()}
    }
    function reset(){
        [name,email,password,cin,cnaps,mle,contact,address,dob,birthPlace,maritalStatus,religion,subject,occupation,hiringDate,contractEndDate,comment].forEach(function(f){f.text=""})
        childCount.value=0;employmentType.currentIndex=0;formError.text=""
    }
    function formData(){return{name:name.text,email:email.text,password:password.text,cin:cin.text,cnaps:cnaps.text,mle:mle.text,contact:contact.text,address:address.text,dob:dob.text,birthPlace:birthPlace.text,children:childCount.value,maritalStatus:maritalStatus.text,religion:religion.text,subject:subject.text,occupation:occupation.text,employmentType:employmentType.currentText,hiringDate:hiringDate.text,contractEndDate:contractEndDate.text,comment:comment.text,photo:""}}
}
