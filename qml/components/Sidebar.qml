import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    clip: true
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#0D2F4B" }
        GradientStop { position: 1.0; color: "#061C2E" }
    }

    property string currentPage: "dashboard"
    signal navigate(string page)

    property var perms: ({})
    function refreshPerms() {
        perms = {
            "audit": school.can("audit.view"),
            "fees": school.can("balances.view"),
            "roles": school.can("roles.manage")
        }
    }
    function pageAllowed(p) {
        return p in perms ? perms[p] : true
    }
    function initials(label) {
        var words = String(label).split(/[\s\/&,-]+/).filter(function(w) { return w.length > 0 })
        var out = ""
        for (var i = 0; i < words.length && out.length < 2; ++i) out += words[i].charAt(0)
        return out.toUpperCase()
    }
    Component.onCompleted: refreshPerms()
    Connections {
        target: school
        function onDataChanged() { root.refreshPerms() }
        function onSessionChanged() { root.refreshPerms() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        Image {
            id: logo
            source: "qrc:/assets/logo.png"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 96
            Layout.preferredWidth: 80
            Layout.topMargin: 6
            Layout.bottomMargin: 12
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#1F4A6E"
        }

        Text {
            text: "NAVIGATION"
            color: "#6F95B3"
            font.pixelSize: 10
            font.bold: true
            font.letterSpacing: 1.5
            Layout.leftMargin: 10
            Layout.topMargin: 12
            Layout.bottomMargin: 6
        }

        ScrollView {
            id: menuScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            ColumnLayout {
                width: menuScroll.availableWidth
                spacing: 3

                Repeater {
                    model: [
                        ["dashboard", "Tableau de bord"],
                        ["students", "Élèves"],
                        ["teachers", "Enseignants"],
                        ["courses", "Cours"],
                        ["exams", "Examens & notes"],
                        ["curriculum", "Matières & emploi du temps"],
                        ["attendance", "Présences"],
                        ["discipline", "Discipline"],
                        ["council", "Délibérations"],
                        ["administration", "Administration scolaire"],
                        ["finreports", "Rapports financiers"],
                        ["treasury", "Caisse, banque et clôtures"],
                        ["finextra", "Bourses, affectations et états"],
                        ["import", "Importation des données"],
                        ["email", "Rapports par e-mail"],
                        ["hr", "Ressources humaines"],
                        ["finance", "Paiements / factures"],
                        ["accounting", "Comptabilité"],
                        ["communication", "Messages / annonces"],
                        ["accounts", "Comptes / sécurité"],
                        ["bulletin", "Bulletins"],
                        ["audit", "Journal d'audit"],
                        ["fees", "Frais et soldes"],
                        ["roles", "Rôles et permissions"]
                    ]
                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        readonly property bool active: root.currentPage === modelData[0]
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        radius: 10
                        visible: root.pageAllowed(modelData[0])
                        color: active ? "#1B4A6E" : (entryArea.containsMouse ? "#143C5C" : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Rectangle {
                            visible: entry.active
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 22
                            radius: 2
                            color: "#0FB9A5"
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 10
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                radius: 14
                                color: entry.active ? "#0F9D8F" : "#173F5F"
                                Text {
                                    anchors.centerIn: parent
                                    text: root.initials(entry.modelData[1])
                                    color: "white"
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: entry.modelData[1]
                                color: entry.active ? "white" : "#C9DCEB"
                                font.pixelSize: 13
                                font.weight: entry.active ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: entryArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.navigate(entry.modelData[0])
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: "#1F4A6E"
            Layout.topMargin: 8
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 10
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: 18
                color: "#0F9D8F"
                Text {
                    anchors.centerIn: parent
                    text: root.initials(school.currentUser)
                    color: "white"
                    font.bold: true
                    font.pixelSize: 12
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    text: school.currentUser
                    color: "white"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: school.currentRole
                    color: "#8FB3CE"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                id: settingsButton
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                color: root.currentPage === "settings" ? "#1B4A6E" : (settingsArea.containsMouse ? "#143C5C" : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "⚙"
                    color: "#C9DCEB"
                    font.pixelSize: 18
                }
                MouseArea {
                    id: settingsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.navigate("settings")
                }
                ToolTip.visible: settingsArea.containsMouse
                ToolTip.text: "Paramètres"
                ToolTip.delay: 400
            }

            Rectangle {
                id: logoutButton
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 17
                color: logoutArea.containsMouse ? "#4A2530" : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text: "⏻"
                    color: logoutArea.containsMouse ? "#FFB4B4" : "#C9DCEB"
                    font.pixelSize: 17
                }
                MouseArea {
                    id: logoutArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: school.logout()
                }
                ToolTip.visible: logoutArea.containsMouse
                ToolTip.text: "Déconnexion"
                ToolTip.delay: 400
            }
        }
    }
}
