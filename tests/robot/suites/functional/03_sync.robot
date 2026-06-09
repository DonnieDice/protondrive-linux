*** Settings ***
Documentation     Functional: 2-way sync + path mapping verification.
...
...               Required CI variables:
...                 PROTON_TEST_EMAIL, PROTON_TEST_PASSWORD
...                 PROTON_SYNC_LOCAL_DIR   — local folder configured for sync
...                                           (e.g. /root/ProtonDrive)
...
...               The sync test creates a file in the local sync folder, waits for
...               the client to pick it up, then verifies the activity indicator
...               appears via OCR (confirming the daemon is active, not just running).
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Suite Cleanup
Force Tags        functional    sync

*** Variables ***
${VM_IP}                   ${EMPTY}
${VM_KEY}                  ${EMPTY}
${PKG_FAMILY}              ${EMPTY}
${PROTON_TEST_EMAIL}       ${EMPTY}
${PROTON_TEST_PASSWORD}    ${EMPTY}
${PROTON_TEST_TOTP_SECRET} ${EMPTY}
${PROTON_SYNC_LOCAL_DIR}   ${EMPTY}
${SYNC_WAIT_SECONDS}       15

*** Keywords ***
Suite Init
    Connect To Test VM    ${VM_IP}    ${VM_KEY}
    Install Visual Test Dependencies    ${PKG_FAMILY}
    Deploy UI Test Script

Suite Cleanup
    Run Keyword If    '${PROTON_SYNC_LOCAL_DIR}' != '${EMPTY}'
    ...    Execute Command    rm -f ${PROTON_SYNC_LOCAL_DIR}/ci-sync-test-*.txt 2>/dev/null || true
    Close All Connections

*** Test Cases ***
Sync Folder Is Configured
    [Documentation]    PROTON_SYNC_LOCAL_DIR must exist on the VM if path mapping is enabled.
    [Tags]    sync    path-mapping
    Skip If    '${PROTON_SYNC_LOCAL_DIR}' == '${EMPTY}'
    ...    Set PROTON_SYNC_LOCAL_DIR CI variable (e.g. /root/ProtonDrive) to enable sync tests
    ${rc}=    Execute Command    test -d ${PROTON_SYNC_LOCAL_DIR}
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0
    ...    Sync dir ${PROTON_SYNC_LOCAL_DIR} does not exist on the VM

File Created Locally Triggers Sync Activity
    [Documentation]    Creates a file in the sync dir; OCR confirms the client shows
    ...                sync/upload activity (not just "process alive").
    [Tags]    compositor    ocr    sync    2way-sync    critical
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials
    Skip If    '${PROTON_SYNC_LOCAL_DIR}' == '${EMPTY}'    PROTON_SYNC_LOCAL_DIR not set
    ${ts}=    Execute Command    date +%s
    Execute Command    printf 'CI 2-way sync test %s\n' '${ts}' > ${PROTON_SYNC_LOCAL_DIR}/ci-sync-test-${ts}.txt
    ${out}    ${rc}=    Execute Command
    ...    PROTON_TEST_EMAIL='${PROTON_TEST_EMAIL}' PROTON_TEST_PASSWORD='${PROTON_TEST_PASSWORD}' PROTON_TEST_TOTP_SECRET='${PROTON_TEST_TOTP_SECRET}' PROTON_SYNC_LOCAL_DIR='${PROTON_SYNC_LOCAL_DIR}' bash /tmp/pd-ui-test.sh functional /tmp/pd-ui-artifacts 2>&1
    ...    return_stdout=True    return_rc=True
    Log    ${out}
    Should Be Equal As Integers    ${rc}    0    2-way sync test failed:\n${out}
    Execute Command    rm -f ${PROTON_SYNC_LOCAL_DIR}/ci-sync-test-${ts}.txt

Path Mapping Settings Are Accessible
    [Documentation]    OCR verifies the sync/path-mapping settings panel is reachable
    ...                from the UI (Settings → Sync or equivalent).
    [Tags]    compositor    ocr    path-mapping
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials
    ${out}=    Execute Command
    ...    tesseract /tmp/pd-ui-artifacts/sidebar_dashboard.png stdout 2>/dev/null
    ...    || echo NOSCREENSHOT
    Should Match Regexp    ${out}    (?i)sync|folder|path|location|settings
    ...    Path mapping / sync settings not found in dashboard OCR: ${out}
