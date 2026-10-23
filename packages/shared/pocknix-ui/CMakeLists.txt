cmake_minimum_required(VERSION 3.25)
project(pocknix-ui LANGUAGES CXX)

find_package(Qt6 6.8 REQUIRED COMPONENTS Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(pocknix-ui-host host/main.cpp)
target_link_libraries(pocknix-ui-host PRIVATE Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickControls2)
# The generated type registrations include the headers by bare name.
target_include_directories(pocknix-ui-host PRIVATE host)

set(QML_FILES
    qml/Pocknix/Ui/Theme.qml
    qml/Pocknix/Ui/AppWindow.qml
    qml/Pocknix/Ui/TabStrip.qml
    qml/Pocknix/Ui/TabPage.qml
    qml/Pocknix/Ui/Tile.qml
    qml/Pocknix/Ui/ActionRow.qml
    qml/Pocknix/Ui/StatusBadge.qml
    qml/Pocknix/Ui/ConfirmSheet.qml
    qml/Pocknix/Ui/LogSheet.qml)
# The module is served from its URI path, not from where the files sit in this tree.
foreach(f IN LISTS QML_FILES)
    get_filename_component(n "${f}" NAME)
    set_source_files_properties("${f}" PROPERTIES QT_RESOURCE_ALIAS "${n}")
endforeach()
set_source_files_properties(qml/Pocknix/Ui/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(pocknix-ui-host
    URI Pocknix.Ui
    VERSION 1.0
    # Kirigami and the controls are system modules loaded at run time, not linked in.
    NO_IMPORT_SCAN
    QML_FILES ${QML_FILES}
    SOURCES host/job.h host/job.cpp host/host.h)

install(TARGETS pocknix-ui-host RUNTIME DESTINATION lib/pocknix-ui)
