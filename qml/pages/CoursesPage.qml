import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    property var teacherList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Cours";font.pixelSize:28;font.bold:true}Item{Layout.fillWidth:true}Button{text:"➕ Créer un cours";onClicked:form.open()}}
        ComboBox{id:filter;model:["Toutes les classes"].concat(school.classes());onCurrentTextChanged:refresh()}
        ListView{Layout.fillWidth:true;Layout.fillHeight:true;model:rows
            delegate:Rectangle{width:parent.width;height:65;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12;spacing:20
                    Label{text:modelData.className;width:110}
                    Label{text:modelData.subject;width:150}
                    Label{text:modelData.title;width:220}
                    Label{text:modelData.teacher;width:170}
                    Label{text:modelData.description;width:250}
                }
            }
        }
    }
    Dialog{id:form;title:"Créer un cours";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            TextField{id:title;placeholderText:"Titre"}
            TextField{id:subject;placeholderText:"Matière"}
            ComboBox{id:classBox;model:school.classes()}
            TextArea{id:description;placeholderText:"Description"}
            ComboBox{id:teacherBox;width:parent.width;model:teacherList;textRole:"label";valueRole:"value"}
        }
        onAccepted:{if(!title.text||!subject.text)return;school.addCourse({title:title.text,subject:subject.text,className:classBox.currentText,description:description.text,teacherId:teacherBox.currentValue>0?teacherBox.currentValue:null});title.text="";subject.text="";description.text=""}
    }
    function refresh(){rows=school.courses(filter.currentIndex>0?filter.currentText:"");var t=[{label:"Non affecté",value:0}],ts=school.teachers();for(var i=0;i<ts.length;i++)t.push({label:ts[i].name,value:ts[i].id});teacherList=t}
}
