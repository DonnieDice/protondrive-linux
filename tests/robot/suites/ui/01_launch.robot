*** Settings ***
Documentation     UI: proton-drive launches and renders a real window under the CI
...               micro-compositor. PASS requires compositor-confirmed window creation
...               (xdotool) + OCR proof of rendered content — process-alive alone is
...               not accepted.
Resource          ../../resources/proton_drive.resource
Resource          ../../resources/compositor.resource
Suite Setup       Suite Init
Suite Teardown    Close All Connections
Force Tags        ui    launch

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
Window Is Created By Compositor
    [Documentation]    xdotool confirms a top-level window exists — not just "process alive".
    [Tags]    compositor    critical
    Compositor Suite Should Pass    smoke

Login Screen Is Rendered With OCR Proof
    [Documentation]    OCR must find "Sign in" or equivalent — blank screen = FAIL.
    [Tags]    ocr    compositor    critical
    ${out}    ${rc}=    Run Compositor Suite    smoke
    Should Contain    ${out}    sign.in    Login screen text not found in OCR output

No Crash Dialog On Launch
    [Documentation]    OCR must NOT find crash/error dialog text on first render.
    [Tags]    compositor    regression
    ${out}    ${rc}=    Run Compositor Suite    smoke
    Should Not Contain    ${out}    segmentation fault
    Should Not Contain    ${out}    core dumped

Screenshots Saved As Artifacts
    [Documentation]    Ensure CI artifact screenshots were captured for debugging.
    [Tags]    artifacts
    ${out}=    Execute Command    ls /tmp/pd-ui-artifacts/*.png 2>/dev/null | wc -l
    Should Be True    ${out} > 0    No screenshots captured — check scrot/imagemagick install
