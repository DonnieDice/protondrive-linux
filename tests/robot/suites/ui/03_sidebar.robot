*** Settings ***
Documentation     UI: sidebar structure + Linux button regression.
...
...               Requires CI variables:
...                 PROTON_TEST_EMAIL      — test account email
...                 PROTON_TEST_PASSWORD   — test account password
...                 PROTON_TEST_TOTP_SECRET (optional) — base32 TOTP secret for 2FA
...
...               Skip gracefully if credentials are absent so the suite can still
...               run in forks / open PRs that don't have the secrets.
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Close All Connections
Force Tags        ui    sidebar

*** Variables ***
${VM_IP}                   ${EMPTY}
${VM_KEY}                  ${EMPTY}
${PKG_FAMILY}              ${EMPTY}
${PROTON_TEST_EMAIL}       ${EMPTY}
${PROTON_TEST_PASSWORD}    ${EMPTY}
${PROTON_TEST_TOTP_SECRET} ${EMPTY}

*** Keywords ***
Suite Init
    Connect To Test VM    ${VM_IP}    ${VM_KEY}
    Install Visual Test Dependencies    ${PKG_FAMILY}
    Deploy UI Test Script
    Set Environment Variable    PROTON_TEST_EMAIL       ${PROTON_TEST_EMAIL}
    Set Environment Variable    PROTON_TEST_PASSWORD    ${PROTON_TEST_PASSWORD}
    Set Environment Variable    PROTON_TEST_TOTP_SECRET ${PROTON_TEST_TOTP_SECRET}

*** Test Cases ***
Sidebar Renders After Login
    [Documentation]    OCR confirms My Files / Shared / Trash visible post-login.
    ...                Skipped if PROTON_TEST_EMAIL is not set.
    [Tags]    compositor    ocr    sidebar    critical
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials — set PROTON_TEST_EMAIL CI variable
    Compositor Suite Should Pass    sidebar

Linux Button Is Present In Sidebar
    [Documentation]    Regression: the Linux-specific sidebar button was broken.
    ...                OCR must find "Linux" or the button label in the sidebar region.
    [Tags]    compositor    ocr    sidebar    linux-button    regression    critical
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials — set PROTON_TEST_EMAIL CI variable
    ${out}    ${rc}=    Run Compositor Suite    sidebar
    Should Match Regexp    ${out}    (?i)linux|linux.app|open.folder|sync.folder
    ...    Linux sidebar button not found in OCR output — sidebar regression detected

Storage Indicator Is Visible
    [Documentation]    Storage usage bar should be present in the sidebar.
    [Tags]    ocr    sidebar
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials
    ${out}    ${rc}=    Run Compositor Suite    sidebar
    Should Match Regexp    ${out}    (?i)storage|gb|mb
