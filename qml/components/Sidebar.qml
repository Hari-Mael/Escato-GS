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
    property string myPhotoUrl: ""
    property string logoSource: "qrc:/assets/logo.png"
    signal navigate(string page)

    property var perms: ({})
    function refreshPerms() {
        myPhotoUrl = school.photoUrl(school.myPhoto())
        logoSource = school.logoUrl()
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

    Popup {
        id: profilePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        width: 360
        padding: 24
        background: Rectangle { radius: 14; color: "white" }

        ColumnLayout {
            spacing: 14
            Label { text: "Ma photo de profil"; font.pixelSize: 18; font.bold: true }
            PhotoPicker {
                id: myPicker
                size: 140
                path: school.myPhoto()
                onPhotoChanged: function(newPath) { school.setMyPhoto(newPath) }
            }
            AppButton { text: "Fermer"; Layout.alignment: Qt.AlignRight; onClicked: profilePopup.close() }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 0

        Image {
            id: logo
            source: root.logoSource
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
                        ["dashboard", "Tableau de bord", "dashboard"],
                        ["students", "Élèves", "school"],
                        ["teachers", "Enseignants", "person_book"],
                        ["courses", "Cours", "menu_book"],
                        ["exams", "Examens & notes", "edit_note"],
                        ["curriculum", "Matières & emploi du temps", "calendar_month"],
                        ["attendance", "Présences", "fact_check"],
                        ["discipline", "Discipline", "gavel"],
                        ["council", "Délibérations", "workspace_premium"],
                        ["administration", "Administration scolaire", "account_balance"],
                        ["finreports", "Rapports financiers", "bar_chart"],
                        ["treasury", "Caisse, banque et clôtures", "account_balance_wallet"],
                        ["finextra", "Bourses, affectations et états", "request_quote"],
                        ["import", "Importation des données", "upload_file"],
                        ["email", "Rapports par e-mail", "mail"],
                        ["hr", "Ressources humaines", "groups"],
                        ["finance", "Paiements / factures", "payments"],
                        ["accounting", "Comptabilité", "receipt_long"],
                        ["communication", "Messages / annonces", "campaign"],
                        ["accounts", "Comptes / sécurité", "lock"],
                        ["bulletin", "Bulletins", "description"],
                        ["audit", "Journal d'audit", "history"],
                        ["fees", "Frais et soldes", "sell"],
                        ["roles", "Rôles et permissions", "admin_panel_settings"]
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
                                    text: entry.modelData[2]
                                    color: "white"
                                    font.family: "Material Symbols Rounded"
                                    font.pixelSize: 17
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
                radius: 10
                color: "#0F9D8F"
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.myPhotoUrl
                    visible: root.myPhotoUrl !== ""
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: profilePopup.open()
                }
                Text {
                    anchors.centerIn: parent
                    text: root.initials(school.currentUser)
                    visible: root.myPhotoUrl === ""
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
                    text: "settings"
                    color: "#C9DCEB"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 22
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
                    text: "logout"
                    color: logoutArea.containsMouse ? "#FFB4B4" : "#C9DCEB"
                    font.family: "Material Symbols Rounded"
                    font.pixelSize: 20
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
