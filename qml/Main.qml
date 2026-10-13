import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO
import "components"
import "pages"

ApplicationWindow {
    id: win
    width: 1440
    height: 900
    visible: true
    title: "ESCATO — Gestion scolaire"
    color: "#F4F7FA"

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

                        AppButton {
                            text: "☰"
                            font.pixelSize: 18
                            implicitWidth: 44
                            onClicked: win.sidebarOpen = !win.sidebarOpen
                        }

                        Item { Layout.fillWidth: true }
                    }

                    StackLayout {
                        id: pages
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        currentIndex: {
                            var map={"dashboard":0,"students":1,"studentForm":2,"studentDetail":3,"teachers":4,"teacherForm":5,"courses":6,"exams":7,"finance":8,"accounting":9,"communication":10,"accounts":11,"bulletin":12,"settings":13,"audit":14}
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
