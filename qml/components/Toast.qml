import QtQuick
import QtQuick.Controls

Popup {
    id: toast
    property string message: ""
    modal: false
    padding: 14
    x: parent ? parent.width - width - 25 : 0
    y: 25
    background: Rectangle { radius: 10; color: "#0B2A43" }
    contentItem: Label { text: toast.message; color: "white" }
    Timer { interval: 2500; running: toast.opened; onTriggered: toast.close() }
}
