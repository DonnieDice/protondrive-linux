*** Settings ***
Documentation     Acceptance: a built proton-drive package installs and runs on its
...               target distro VM. Parametrized — CI passes one VM's variables per run:
...                 robot -v VM_IP:.. -v VM_KEY:.. -v PKG_FAMILY:deb -v LOCAL_PKG:artifacts/x.deb \
...                       tests/robot/suites/smoke/install_verify.robot
Resource          ../../resources/proton_drive.resource
Suite Setup       Connect To Test VM    ${VM_IP}    ${VM_KEY}
Suite Teardown    Close All Connections
Force Tags        acceptance    install

*** Variables ***
${VM_IP}          ${EMPTY}
${VM_KEY}         ${EMPTY}
${PKG_FAMILY}     ${EMPTY}
${LOCAL_PKG}      ${EMPTY}

*** Test Cases ***
Package Installs Cleanly
    [Documentation]    The native package manager installs the artifact without error.
    ${remote}=    Copy Package To VM    ${LOCAL_PKG}
    Install Package On VM    ${remote}    ${PKG_FAMILY}

Binary Is Installed And On PATH
    Proton Drive Binary Should Be Installed

Binary Responds To Version Or Help
    Proton Drive Should Report Version

Desktop Entry Is Installed
    [Tags]    packaging-regression
    Desktop Entry Should Be Installed

Application Icon Is Installed
    [Tags]    packaging-regression
    Application Icon Should Be Installed

GUI Loads Under CI Micro-Compositor
    [Documentation]    Determines visual load via a headless compositor (no AI).
    [Tags]    gui
    GUI Should Load Under CI Compositor
