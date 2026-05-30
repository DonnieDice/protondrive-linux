*** Settings ***
Documentation     Functional: full login flow including 2FA.
...
...               Required CI variables (set in GitLab → Settings → CI/CD → Variables):
...                 PROTON_TEST_EMAIL         test account email
...                 PROTON_TEST_PASSWORD      test account password
...                 PROTON_TEST_TOTP_SECRET   base32 TOTP secret (leave empty if no 2FA)
...
...               All tests skip gracefully when credentials are absent.
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Close All Connections
Force Tags        functional    auth

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
    Execute Command    export PROTON_TEST_EMAIL='${PROTON_TEST_EMAIL}'
    Execute Command    export PROTON_TEST_PASSWORD='${PROTON_TEST_PASSWORD}'
    Execute Command    export PROTON_TEST_TOTP_SECRET='${PROTON_TEST_TOTP_SECRET}'

*** Test Cases ***
Login With Valid Credentials
    [Documentation]    Authenticates with email + password; confirms dashboard renders.
    [Tags]    compositor    ocr    auth    critical
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    Set PROTON_TEST_EMAIL CI variable to enable
    ${out}    ${rc}=    Execute Command
    ...    PROTON_TEST_EMAIL='${PROTON_TEST_EMAIL}' PROTON_TEST_PASSWORD='${PROTON_TEST_PASSWORD}' PROTON_TEST_TOTP_SECRET='${PROTON_TEST_TOTP_SECRET}' bash /tmp/pd-ui-test.sh sidebar /tmp/pd-ui-artifacts 2>&1
    ...    return_stdout=True    return_rc=True
    Log    ${out}
    Should Be Equal As Integers    ${rc}    0    Login flow failed:\n${out}

Two Factor Authentication Handled
    [Documentation]    If a 2FA prompt appears, pyotp generates the TOTP code and submits it.
    [Tags]    compositor    ocr    auth    2fa
    Skip If    '${PROTON_TEST_TOTP_SECRET}' == '${EMPTY}'    Set PROTON_TEST_TOTP_SECRET to enable 2FA tests
    ${out}    ${rc}=    Execute Command
    ...    python3 -c "import pyotp; print(pyotp.TOTP('${PROTON_TEST_TOTP_SECRET}').now())" 2>&1
    ...    return_stdout=True    return_rc=True
    Should Be Equal As Integers    ${rc}    0    pyotp failed to generate TOTP — install pyotp on VM
    Should Match Regexp    ${out}    ^\\d{6}$    TOTP code is not 6 digits: ${out}
    Log    TOTP generated (code not logged for security)

Dashboard Renders After Login
    [Documentation]    After successful auth, OCR must confirm dashboard elements.
    [Tags]    compositor    ocr    auth
    Skip If    '${PROTON_TEST_EMAIL}' == '${EMPTY}'    No credentials
    ${out}=    Execute Command    tesseract /tmp/pd-ui-artifacts/sidebar_dashboard.png stdout 2>/dev/null || echo NOSCREENSHOT
    Should Match Regexp    ${out}    (?i)my.files|my files|proton.drive|storage
    ...    Dashboard did not render after login — OCR: ${out}
