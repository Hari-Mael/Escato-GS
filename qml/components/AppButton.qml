import QtQuick
import QtQuick.Controls

Button {
    id: control

    readonly property color accent: "#0F9D8F"
    readonly property color accentDark: "#0B7F74"
    readonly property color accentLight: "#E6F6F4"

    hoverEnabled: true
    padding: 10
    leftPadding: 18
    rightPadding: 18
    font.pixelSize: 14
    font.weight: Font.DemiBold

    contentItem: Text {
        text: control.text
        font: control.font
        color: !control.enabled ? "#7A8790" : control.highlighted ? "white" : accentDark
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: 10
        color: {
            if (!control.enabled) return "#D5DEE3"
            if (control.highlighted) return control.down ? control.accentDark : (control.hovered ? "#12B0A0" : control.accent)
            return control.down ? "#D2EFEB" : (control.hovered ? "#D8F2EE" : control.accentLight)
        }
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
