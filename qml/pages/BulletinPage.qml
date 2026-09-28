import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    property var result:({})
    ColumnLayout{anchors.fill:parent;spacing:15
        Label{text:"Bulletins";font.pixelSize:28;font.bold:true}
        RowLayout{ComboBox{id:students;model:rows;Layout.fillWidth:true;textRole:"label";valueRole:"value"};ComboBox{id:term;model:school.terms()};Button{text:"Générer";onClicked:result=school.bulletin(students.currentValue,term.currentText)}}
        Rectangle{Layout.fillWidth:true;Layout.fillHeight:true;color:"white";radius:14
            Column{anchors.fill:parent;anchors.margins:20;spacing:12
                Label{text:result.student ? result.student.firstName+" "+result.student.lastName : "Sélectionnez un élève";font.pixelSize:24;font.bold:true}
                Label{text:result.generalAverage ? "Moyenne générale : "+result.generalAverage+"/20" : ""}
                Repeater{model:result.subjects||[];delegate:Label{text:modelData.subject+" : "+modelData.average+"/20"}}
            }
        }
    }
    Connections{target:school;function onDataChanged(){loadStudents()}}
    Component.onCompleted:loadStudents()
    function loadStudents(){
        var s=school.students();var a=[];for(var i=0;i<s.length;i++)a.push({label:s[i].firstName+" "+s[i].lastName+" — "+s[i].className,value:s[i].id});rows=a
    }
}
