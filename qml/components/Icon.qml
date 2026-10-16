import QtQuick

Text {
    id: root
    property string name: ""
    property int size: 20

    text: name
    font.family: "Material Symbols Rounded"
    font.pixelSize: size
    color: "#0B7F74"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
