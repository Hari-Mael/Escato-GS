import QtQuick
import QtQuick.Controls

Dialog {
    id: root
    property string message: "Confirmer la suppression ?"
    property int targetId: 0
    signal confirmed(int id)

    title: "Confirmer la suppression"
    modal: true
    anchors.centerIn: Overlay.overlay
    standardButtons: Dialog.Yes | Dialog.No
    width: 380

    Label {
        width: parent.width
        text: root.message
        wrapMode: Text.WordWrap
    }

    function ask(id) {
        targetId = id || 0
        open()
    }

    onAccepted: confirmed(targetId)
}
