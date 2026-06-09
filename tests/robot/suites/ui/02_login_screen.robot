*** Settings ***
Documentation     UI: login screen structure tests — verifies all required form
...               elements are present and correctly rendered before any auth attempt.
...               These run against the pre-login state; no credentials required.
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Close All Connections
Force Tags        ui    login-screen

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
Login Form Is Fully Rendered
    [Documentation]    OCR confirms email field, password field and sign-in button all
    ...                visible — not just "window exists".
    [Tags]    compositor    ocr    critical
    Compositor Suite Should Pass    ui

Email Field Is Present
    [Documentation]    OCR confirms the email/username input label is visible.
    [Tags]    ocr
    ${out}    ${rc}=    Run Compositor Suite    ui
    Should Match Regexp    ${out}    (?i)email|username

Password Field Is Present
    [Tags]    ocr
    ${out}    ${rc}=    Run Compositor Suite    ui
    Should Match Regexp    ${out}    (?i)password

Sidebar Is Hidden Before Login
    [Documentation]    No sidebar content (My Files, Trash, etc.) should be visible
    ...                before the user authenticates.
    [Tags]    compositor    ocr    regression
    ${out}    ${rc}=    Run Compositor Suite    ui
    Should Contain    ${out}    PASS    Sidebar-hidden-pre-login check failed
