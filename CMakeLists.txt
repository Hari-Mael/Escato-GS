cmake_minimum_required(VERSION 3.21)
project(ESCATO LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Sql PrintSupport Widgets)

qt_standard_project_setup()

qt_add_executable(ESCATO
    src/main.cpp
    src/core/SchoolApp.cpp
    src/core/SchoolApp.h
    src/core/Database.cpp
    src/core/Database.h
    src/core/PrintManager.cpp
    src/core/PrintManager.h
)

qt_add_qml_module(ESCATO
    URI ESCATO
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/Sidebar.qml
        qml/components/StatCard.qml
        qml/components/Toast.qml
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
)

qt_add_resources(ESCATO "escato_resources"
    PREFIX "/"
    FILES
        assets/logo.png
)

target_include_directories(ESCATO PRIVATE src)

target_link_libraries(ESCATO
    PRIVATE Qt6::Quick Qt6::Sql Qt6::PrintSupport Qt6::Widgets
)
