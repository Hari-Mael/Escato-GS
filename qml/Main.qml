import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO
import "components"
import "pages"

import QtQuick.Window

ApplicationWindow {
    id: win
    width: 1440
    height: 900
    minimumWidth: 900
    minimumHeight: 600
    visibility: Window.Maximized
    onWidthChanged: sidebarOpen = width >= 1200
    Component.onCompleted: sidebarOpen = width >= 1200
    visible: true
    title: "ESCATO — Gestion scolaire"
    color: "#F4F7FA"

    FontLoader {
        id: iconFont
        source: "qrc:/assets/fonts/MaterialSymbolsRounded.ttf"
    }

    Loader {
        anchors.fill: parent
        sourceComponent: school.loggedIn ? (school.currentRole === "parent" || school.currentRole === "eleve" ? familyComponent : appComponent) : (school.needsSetup ? setupComponent : loginComponent)
    }

    Component {
        id: loginComponent
        LoginPage { onSuccess: {} }
    }

    Component {
        id: setupComponent
        SetupPage {}
    }

    Component {
        id: familyComponent
        FamilyPortal {}
    }

    Component {
        id: appComponent
        RowLayout {
            spacing: 0

            Sidebar {
                id: side
                currentPage: win.page
                Layout.preferredWidth: win.sidebarOpen ? 240 : 0
                Layout.fillHeight: true
                visible: Layout.preferredWidth > 0
                onNavigate: function(target) { win.page = target }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 28
                    anchors.topMargin: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true

                        Item {
                            implicitWidth: 40
                            implicitHeight: 40

                            Icon {
                                anchors.centerIn: parent
                                name: "menu"
                                size: 24
                                color: menuArea.containsMouse ? "#0F9D8F" : "#0B7F74"
                            }

                            MouseArea {
                                id: menuArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.sidebarOpen = !win.sidebarOpen
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }

                    Flickable {
                        id: hScroll
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: pages.width
                        contentHeight: pages.height
                        flickableDirection: Flickable.HorizontalFlick
                        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    StackLayout {
                        id: pages
                        width: Math.max(hScroll.width, 980)
                        height: hScroll.height
                        currentIndex: {
                            var map={"dashboard":0,"students":1,"studentForm":2,"studentDetail":3,"teachers":4,"teacherForm":5,"courses":6,"exams":7,"finance":8,"accounting":9,"communication":10,"accounts":11,"bulletin":12,"settings":13,"audit":14,"fees":15,"roles":16,"curriculum":17,"attendance":18,"discipline":19,"council":20,"administration":21,"finreports":22,"treasury":23,"finextra":24,"import":25,"email":26,"hr":27}
                            return map[win.page]===undefined?0:map[win.page]
                        }

                        DashboardPage {}

                        StudentsPage {
                            onRegisterRequested: win.page="studentForm"
                            onDetailRequested: function(id){ win.studentDetailId=id; win.page="studentDetail" }
                        }

                        StudentFormPage { onSaved: win.page="students" }

                        StudentDetailPage {
                            studentId: win.studentDetailId
                            onBack: win.page="students"
                        }

                        TeachersPage { onCreateRequested: win.page="teacherForm" }
                        TeacherFormPage { onSaved: win.page="teachers" }
                        CoursesPage {}
                        ExamsPage {}
                        FinancePage {}
                        AccountingPage {}
                        CommunicationPage {}
                        AccountsPage {}
                        BulletinPage {}
                        SettingsPage {}
                        AuditPage {}
                        FeesPage {}
                        RolesPage {}
                        CurriculumPage {}
                        AttendancePage {}
                        DisciplinePage {}
                        CouncilPage {}
                        AdministrationPage {}
                        FinanceReportsPage {}
                        AccountingExtraPage {}
                        FinanceExtraPage {}
                        ImportPage {}
                        EmailPage {}
                        HrPage {}
                    }
                    }
                }
            }
        }
    }

    property string page: "dashboard"
    property bool sidebarOpen: true
    property int studentDetailId: 0

    Toast { id: toast }

    Announcement { id: announcement }

    Connections {
        target: school
        function onErrorOccurred(message) { toast.message = message; toast.open() }
        function onSessionChanged() {
            if (school.loggedIn) {
                announcement.show("AMETUR COR JESUS")
            } else {
                win.page = "dashboard"
                announcement.show("AMETUR COR MARIAE")
            }
        }
    }
}
