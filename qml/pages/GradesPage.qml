import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
Item{
    property int examId:0
    property var rows:[]
    Component.onCompleted:refresh()
    onExamIdChanged:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ListView{anchors.fill:parent;model:rows
        delegate:RowLayout{width:parent.width;height:50
            Label{text:modelData.lastName+" "+modelData.firstName;Layout.preferredWidth:240}
            AppTextField{id:score;Layout.preferredWidth:100;placeholderText:"Note";text:(modelData.score===undefined||modelData.score===null||modelData.score==="")?"":String(modelData.score)}
            AppTextField{id:comment;Layout.fillWidth:true;placeholderText:"Commentaire";text:modelData.comment||""}
            AppButton{text:"Enregistrer";enabled:score.text!=="";onClicked:school.saveGrade(examId,modelData.studentId,parseFloat(score.text.replace(",",".")),comment.text)}
        }
    }
    function refresh(){rows=school.grades(examId)}
}
