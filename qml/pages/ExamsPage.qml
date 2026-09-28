import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
Item{
    property var rows:[]
    property var courseList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Examens";font.pixelSize:28;font.bold:true};Item{Layout.fillWidth:true};Button{text:"➕ Planifier";onClicked:form.open()}}
        ListView{Layout.fillWidth:true;Layout.fillHeight:true;model:rows
            delegate:Rectangle{width:parent.width;height:62;color:index%2?"#FAFBFC":"white"
                Row{anchors.fill:parent;anchors.margins:12;spacing:20
                    Label{text:modelData.date;width:110};Label{text:modelData.className;width:100};Label{text:modelData.subject;width:150};Label{text:modelData.title;width:200};Label{text:modelData.term;width:120};Label{text:"/ "+modelData.maxScore;width:70}
                    Button{text:"Notes";onClicked:{gradeExamId=modelData.id;grades.open()}}
                }
            }
        }
    }
    property int gradeExamId:0
    Dialog{id:form;title:"Planifier un examen";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            ComboBox{id:courseBox;width:parent.width;model:courseList;textRole:"label";valueRole:"id"}
            TextField{id:title;placeholderText:"Titre"}
            ComboBox{id:term;model:school.terms()}
            TextField{id:date;placeholderText:"AAAA-MM-JJ"}
            SpinBox{id:maxScore;from:1;to:100;value:20}
        }
        onAccepted:{if(courseBox.currentValue===undefined||!title.text||!/^\d{4}-\d{2}-\d{2}$/.test(date.text))return;school.addExam({courseId:courseBox.currentValue,title:title.text,term:term.currentText,date:date.text,maxScore:maxScore.value});title.text="";date.text=""}
    }
    Dialog{id:grades;title:"Saisie des notes";modal:true;anchors.centerIn:Overlay.overlay;width:900;height:600;standardButtons:Dialog.Close
        GradesPage{anchors.fill:parent;examId:gradeExamId}
    }
    function refresh(){rows=school.exams();var c=school.courses(),l=[];for(var i=0;i<c.length;i++)l.push({label:c[i].className+" — "+c[i].subject+" — "+c[i].title,id:c[i].id});courseList=l}
}
