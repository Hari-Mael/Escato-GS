cmake_minimum_required(VERSION 3.21)
project(ESCATO LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql PrintSupport Widgets Network)

qt_standard_project_setup()

qt_add_executable(escato_app
    src/main.cpp
    src/core/SchoolApp.cpp
    src/core/SchoolApp.h
    src/core/Database.cpp
    src/core/Database.h
    src/core/PrintManager.cpp
    src/core/PrintManager.h
    src/third_party/qrcodegen/qrcodegen.cpp
    src/third_party/qrcodegen/qrcodegen.hpp
)

set_target_properties(escato_app PROPERTIES
    WIN32_EXECUTABLE TRUE
)

qt_add_qml_module(escato_app
    URI ESCATO
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/Sidebar.qml
        qml/components/StatCard.qml
        qml/components/Toast.qml
        qml/components/AppButton.qml
        qml/components/AppTextField.qml
        qml/components/Announcement.qml
        qml/pages/LoginPage.qml
        qml/pages/SetupPage.qml
        qml/pages/DashboardPage.qml
        qml/pages/StudentsPage.qml
        qml/pages/StudentFormPage.qml
        qml/pages/StudentDetailPage.qml
        qml/pages/TeachersPage.qml
        qml/pages/TeacherFormPage.qml
        qml/pages/CoursesPage.qml
        qml/pages/ExamsPage.qml
        qml/pages/GradesPage.qml
        qml/pages/FinancePage.qml
        qml/pages/AccountingPage.qml
        qml/pages/CommunicationPage.qml
        qml/pages/AccountsPage.qml
        qml/pages/BulletinPage.qml
        qml/pages/SettingsPage.qml
        qml/pages/FamilyPortal.qml
        qml/pages/AuditPage.qml
        qml/pages/FeesPage.qml
        qml/pages/RolesPage.qml
        qml/pages/CurriculumPage.qml
        qml/pages/AttendancePage.qml
        qml/pages/DisciplinePage.qml
        qml/pages/CouncilPage.qml
        qml/pages/AdministrationPage.qml
        qml/pages/FinanceReportsPage.qml
        qml/pages/AccountingExtraPage.qml
        qml/pages/FinanceExtraPage.qml
        qml/pages/ImportPage.qml
)

qt_add_resources(escato_app "escato_resources"
    PREFIX "/"
    FILES
        assets/logo.png
)

target_include_directories(escato_app PRIVATE src)

target_link_libraries(escato_app
    PRIVATE Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::PrintSupport Qt6::Widgets Qt6::Network
)
