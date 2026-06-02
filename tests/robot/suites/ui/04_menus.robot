*** Settings ***
Documentation     UI: menu bar and in-app menu accessibility tests.
...               Tests that menus are present and keyboard-navigable.
...               No credentials required.
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Close All Connections
Force Tags        ui    menus

*** Variables ***
${VM_IP}       ${EMPTY}
${VM_KEY}      ${EMPTY}
${PKG_FAMILY}  ${EMPTY}

*** Keywords ***
Suite Init
    Connect To Test VM    ${VM_IP}    ${VM_KEY}
    Install Visual Test Dependencies    ${PKG_FAMILY}
    Deploy UI Test Script

*** Test Cases ***
Menu Bar Is Accessible
    [Documentation]    OCR confirms at least one menu-bar item is visible (File/View/Help).
    [Tags]    compositor    ocr    menus
    Compositor Suite Should Pass    menus

App Is Keyboard-Navigable
    [Documentation]    Pressing F1 / Alt should produce a visible response (help panel or
    ...                menu highlight) without crashing the app.
    [Tags]    compositor    keyboard
    ${out}    ${rc}=    Run Compositor Suite    menus
    Should Not Contain    ${out}    ✗ FAIL
    ...    Menu keyboard navigation test failed:\n${out}
