import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item {
    signal createRequested()
    property var rows: []
    property string searchText:""
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{
        anchors.fill:parent;spacing:15
        RowLayout{Layout.fillWidth:true;Label{text:"Enseignants";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"➕ Ajouter";onClicked:createRequested()};Button{text:"🖨 Imprimer";onClicked:printer.printTeacherList()}}
        TextField{Layout.fillWidth:true;placeholderText:"Rechercher enseignant, matière, CIN...";onTextChanged:searchText=text;onEditingFinished:refresh()}
        ListView{
            Layout.fillWidth:true;Layout.fillHeight:true;model:rows;clip:true
            delegate:Rectangle{width:parent.width;height:65;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12
                    Label{text:modelData.name;width:170}
                    Label{text:modelData.email;width:210}
                    Label{text:modelData.subject;width:160}
                    Label{text:modelData.contact;width:140}
                    Label{text:modelData.status;width:100}
                }
            }
        }
    }
    function refresh(){rows=school.teachers(searchText)}
}
