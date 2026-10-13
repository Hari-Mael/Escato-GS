import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
Item{
    property var inv:[]
    property var pays:[]
    property var studentList:[]
    Component.onCompleted:refresh()
    Connections{target:school;function onDataChanged(){refresh()}}
    ColumnLayout{anchors.fill:parent;spacing:15
        RowLayout{Label{text:"Paiements & factures";font.pixelSize:28;font.bold:true}Item{Layout.fillWidth:true}AppButton{text:"Nouveau paiement";highlighted:true;onClicked:payDialog.open()}AppButton{text:"Tarif mensuel";onClicked:feeDialog.open()}AppButton{text:"Générer factures du mois";onClicked:school.generateMonthlyInvoices(Qt.formatDate(new Date(),"yyyy-MM"))}AppButton{text:"Traiter rappels";onClicked:school.processPaymentReminders()}}
        TabBar{id:tabs;TabButton{text:"Factures"}TabButton{text:"Paiements"}}
        StackLayout{currentIndex:tabs.currentIndex;Layout.fillWidth:true;Layout.fillHeight:true
            ListView{model:inv;delegate:Rectangle{width:parent.width;height:55;color:index%2?"#FAFBFC":"white";Row{anchors.fill:parent;anchors.margins:12;spacing:30;Label{text:modelData.student;width:220}Label{text:modelData.month;width:110}Label{text:modelData.dueDate;width:110}Label{text:modelData.amount+" Ar";width:120}Label{text:modelData.status}}}}
            ListView{model:pays;delegate:Rectangle{width:parent.width;height:55;color:index%2?"#FAFBFC":"white";Row{anchors.fill:parent;anchors.margins:12;spacing:30;Label{text:modelData.student;width:220}Label{text:modelData.amount+" Ar";width:120}Label{text:modelData.method;width:130}Label{text:modelData.paidAt;width:120}Label{text:modelData.payerRole}}}}
        }
    }
    Dialog{id:payDialog;title:"Enregistrer un paiement";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            ComboBox{id:payStudent;width:parent.width;model:studentList;textRole:"label";valueRole:"value"}
            AppTextField{id:payAmount;width:parent.width;placeholderText:"Montant (Ar)"}
            ComboBox{id:payMethod;width:parent.width;model:school.paymentMethods()}
            AppTextField{id:payRef;width:parent.width;placeholderText:"Référence (facultatif)"}
        }
        onAccepted:{
            var a=parseFloat(payAmount.text.replace(",","."))
            if(payStudent.currentValue===undefined||!(a>0))return
            school.addPayment({studentId:payStudent.currentValue,amount:a,method:payMethod.currentText,reference:payRef.text,paidAt:Qt.formatDateTime(new Date(),"yyyy-MM-dd hh:mm:ss"),notes:""})
            payAmount.text="";payRef.text=""
        }
    }
    Dialog{id:feeDialog;title:"Tarif mensuel d'un élève";modal:true;anchors.centerIn:Overlay.overlay;standardButtons:Dialog.Ok|Dialog.Cancel
        Column{spacing:8;width:400
            ComboBox{id:feeStudent;width:parent.width;model:studentList;textRole:"label";valueRole:"value"}
            AppTextField{id:feeAmount;width:parent.width;placeholderText:"Montant mensuel (Ar)"}
        }
        onAccepted:{
            var a=parseFloat(feeAmount.text.replace(",","."))
            if(feeStudent.currentValue===undefined||!(a>0))return
            school.setStudentFee(feeStudent.currentValue,a)
            feeAmount.text=""
        }
    }
    function refresh(){
        inv=school.invoices();pays=school.payments()
        var s=school.students(),l=[]
        for(var i=0;i<s.length;i++)l.push({label:s[i].lastName+" "+s[i].firstName+" — "+s[i].className,value:s[i].id})
        studentList=l
    }
}
