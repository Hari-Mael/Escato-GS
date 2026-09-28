import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import ESCATO

ApplicationWindow {
    id: win
    width: 1440
    height: 900
    visible: true
    title: "ESCATO — Gestion scolaire"
    color: "#F4F7FA"

    Loader {
        anchors.fill: parent
        sourceComponent: school.loggedIn ? appComponent : (school.needsSetup ? setupComponent : loginComponent)
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
        id: appComponent
        RowLayout {
            spacing: 0
            Sidebar {
                id: side
                currentPage: win.page
                Layout.preferredWidth: 240
                Layout.fillHeight: true
                onNavigate: function(target) { win.page = target }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                StackLayout {
                    id: pages
                    anchors.fill: parent
                    anchors.margins: 28
                    currentIndex: {
                        var map={"dashboard":0,"students":1,"studentForm":2,"studentDetail":3,"teachers":4,"teacherForm":5,"courses":6,"exams":7,"finance":8,"accounting":9,"communication":10,"accounts":11,"bulletin":12}
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
                }
            }
        }
    }

    property string page: "dashboard"
    property int studentDetailId: 0

    Toast { id: toast }

    Connections {
        target: school
        function onErrorOccurred(message) { toast.message = message; toast.open() }
        function onSessionChanged() {
            if (!school.loggedIn) win.page = "dashboard"
        }
    }
}
