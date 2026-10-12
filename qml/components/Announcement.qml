import QtQuick
import QtQuick.Controls

Popup {
    id: announcement

    property string message: ""

    function show(text) {
        close()
        message = text
        open()
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: false
    focus: false
    width: Math.min(parent ? parent.width - 120 : 640, 680)
    padding: 44

    background: Rectangle {
        radius: 22
        color: "#0B2A43"
        border.color: "#0F9D8F"
        border.width: 2
    }

    contentItem: Label {
        text: announcement.message
        color: "white"
        font.family: "Georgia"
        font.pixelSize: 34
        font.weight: Font.DemiBold
        font.letterSpacing: 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
    }

    Timer {
        id: hideTimer
        interval: 15000
        onTriggered: announcement.close()
    }

    onOpened: hideTimer.restart()
}
