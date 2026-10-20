import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: root
    property string heading: ""
    property var items: []

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    padding: 24
    width: 470
    background: Rectangle { radius: 14; color: "white" }

    function fmtAny(v) {
        var s = String(v === undefined || v === null ? "" : v)
        var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
        return m ? m[3] + "-" + m[2] + "-" + m[1] : s
    }
    function show(title, list) {
        heading = title
        items = list.map(function(p) { return [p[0], fmtAny(p[1])] })
        open()
    }

    ColumnLayout {
        width: root.width - root.padding * 2
        spacing: 10

        Label {
            text: root.heading
            font.pixelSize: 20
            font.bold: true
            color: "#0B2A43"
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#E3E8EE" }

        Repeater {
            model: root.items
            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Label {
                    text: modelData[0]
                    color: "#667085"
                    Layout.preferredWidth: 170
                    wrapMode: Text.WordWrap
                }
                Label {
                    text: (modelData[1] === "" || modelData[1] === null) ? "—" : modelData[1]
                    font.bold: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }
        }

        AppButton {
            text: "Fermer"
            Layout.alignment: Qt.AlignRight
            onClicked: root.close()
        }
    }
}
