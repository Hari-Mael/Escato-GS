import QtQuick
import QtQuick.Controls

TextField {
    id: field

    color: "#1F2937"
    placeholderTextColor: "#8A97A6"
    selectionColor: "#0F9D8F"
    selectedTextColor: "white"
    font.pixelSize: 14
    leftPadding: 12
    rightPadding: 12
    topPadding: 10
    bottomPadding: 10

    background: Rectangle {
        radius: 10
        color: field.activeFocus ? "#E6F6F4" : "#F1F5F7"
        border.width: 0
    }
}
