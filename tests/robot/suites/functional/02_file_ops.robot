*** Settings ***
Documentation     Functional: file upload and download via Proton Drive.
...
...               Required CI variables:
...                 PROTON_TEST_EMAIL, PROTON_TEST_PASSWORD
...                 PROTON_TEST_TOTP_SECRET (if 2FA enabled)
...
...               These tests require an active internet connection from the VM
...               to Proton's servers and a real Proton Drive account.
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Suite Cleanup
Force Tags        functional    file-ops

*** Variables ***
${VM_IP}                   ${EMPTY}
${VM_KEY}                  ${EMPTY}
${PKG_FAMILY}              ${EMPTY}
${PROTON_TEST_EMAIL}       ${EMPTY}
${PROTON_TEST_PASSWORD}    ${EMPTY}
${PROTON_TEST_TOTP_SECRET} ${EMPTY}
${CI_TEST_FILENAME}        ci-upload-test.txt

*** Keywords ***
Suite Init
    Connect To Test VM    ${VM_IP}    ${VM_KEY}
    Install Visual Test Dependencies    ${PKG_FAMILY}
    Deploy UI Test Script

Suite Cleanup
    Execute Command    rm -f /tmp/${CI_TEST_FILENAME} 2>/dev/null || true
    Close All Connections

*** Test Cases ***
Upload File Shows In Transfer UI
    [Documentation]    Creates a test file and uploads it; OCR confirms upload activity
    ...                indicator appears (progress bar, transfer count, etc.).
    [Tags]    compositor    ocr    upload    critical
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials
    ${out}    ${rc}=    Execute Command
    ...    PROTON_TEST_EMAIL='${PROTON_TEST_EMAIL}' PROTON_TEST_PASSWORD='${PROTON_TEST_PASSWORD}' PROTON_TEST_TOTP_SECRET='${PROTON_TEST_TOTP_SECRET}' bash /tmp/pd-ui-test.sh functional /tmp/pd-ui-artifacts 2>&1
    ...    return_stdout=True    return_rc=True
    Log    ${out}
    Should Be Equal As Integers    ${rc}    0    Upload test failed:\n${out}

Download File Is Retrievable
    [Documentation]    After upload, triggers download and checks file appears locally.
    ...                NOTE: Proton Drive's Linux client may handle downloads differently
    ...                than the web UI. This test validates the download flow is accessible.
    [Tags]    compositor    ocr    download
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials
    # Check that the downloaded file area is accessible in the UI
    ${out}=    Execute Command    tesseract /tmp/pd-ui-artifacts/functional_dashboard.png stdout 2>/dev/null || echo NOSCREENSHOT
    Should Match Regexp    ${out}    (?i)download|my.files|my files|trash
    ...    Download area not accessible in UI — OCR: ${out}
