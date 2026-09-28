import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Comptes & sécurité";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"Créer un compte";onClicked:create.open()}}
        ListView{Layout.fillWidth:true;Layout.fillHeight:true;model:rows
            delegate:Rectangle{width:parent.width;height:65;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12;spacing:25
                    Label{text:modelData.name;width:180};Label{text:modelData.email;width:220};Label{text:modelData.role;width:130};Label{text:modelData.status;width:100};Label{text:modelData.blockedReason;width:250}
                    Button{text:"Bloquer";enabled:modelData.status==="active";onClicked:school.blockUser(modelData.id,"administratif","Blocage administratif")}
                    Button{text:"Débloquer";enabled:modelData.status!=="active";onClicked:school.unblockUser(modelData.id)}
                }
            }
        }
    }
    Dialog{id:create;title:"Créer un compte";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            TextField{id:name;placeholderText:"Nom"}
            TextField{id:email;placeholderText:"E-mail"}
            TextField{id:password;placeholderText:"Mot de passe";echoMode:TextInput.Password}
            ComboBox{id:role;model:school.roles()}
        }
        onAccepted:school.createUser({name:name.text,email:email.text,password:password.text,role:role.currentText})
    }
    function refresh(){rows=school.users()}
}
