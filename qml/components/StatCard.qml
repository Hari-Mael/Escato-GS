import QtQuick
import QtQuick.Controls

Rectangle {
    property string title
    property string value
    implicitWidth: 210
    implicitHeight: 105
    radius: 14
    color: "white"
    border.color: "#E4EAF0"
    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 8
        Label { text: title; color: "#667085" }
        Label { text: value; font.pixelSize: 27; font.bold: true; color: "#0B2A43" }
    }
}
