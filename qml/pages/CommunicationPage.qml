import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var msgs:[]
    property var anns:[]
    property var userList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Communication";font.pixelSize:28;font.bold:true}Item{Layout.fillWidth:true}Button{text:"Nouveau message";onClicked:message.open()}Button{text:"Nouvelle annonce";onClicked:announcement.open()}}
        TabBar{id:tabs;TabButton{text:"Messages"}TabButton{text:"Annonces"}}
        StackLayout{currentIndex:tabs.currentIndex;Layout.fillWidth:true;Layout.fillHeight:true
            ListView{model:msgs;delegate:Rectangle{width:parent.width;height:75;color:index%2?"#FAFBFC":"white";Column{anchors.fill:parent;anchors.margins:12;Label{text:modelData.subject;font.bold:true}Label{text:modelData.sender+" → "+modelData.recipient}Label{text:modelData.body;elide:Text.ElideRight;width:parent.width}}}}
            ListView{model:anns;delegate:Rectangle{width:parent.width;height:90;color:index%2?"#FAFBFC":"white";Column{anchors.fill:parent;anchors.margins:12;Label{text:modelData.title;font.bold:true}Label{text:modelData.body;elide:Text.ElideRight}Label{text:modelData.eventDate}}}}
        }
    }
    Dialog{id:message;title:"Envoyer un message";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:450
            ComboBox{id:recipientBox;width:parent.width;model:userList;textRole:"label";valueRole:"value"}
            TextField{id:msgSubject;placeholderText:"Objet"}
            TextArea{id:msgBody;placeholderText:"Message";width:450;height:160}
        }
        onAccepted:{if(recipientBox.currentValue===undefined||!msgSubject.text||!msgBody.text)return;school.sendMessage(recipientBox.currentValue,msgSubject.text,msgBody.text);msgSubject.text="";msgBody.text=""}
    }
    Dialog{id:announcement;title:"Nouvelle annonce";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:450
            TextField{id:annTitle;placeholderText:"Titre"}
            TextField{id:eventDate;placeholderText:"Date événement"}
            TextArea{id:annBody;placeholderText:"Contenu";width:450;height:160}
        }
        onAccepted:{if(!annTitle.text||!annBody.text)return;school.addAnnouncement({title:annTitle.text,body:annBody.text,eventDate:eventDate.text});annTitle.text="";annBody.text="";eventDate.text=""}
    }
    function refresh(){msgs=school.messages();anns=school.announcements();var u=school.users(),l=[];for(var i=0;i<u.length;i++)l.push({label:u[i].name+" ("+u[i].role+")",value:u[i].id});userList=l}
}
