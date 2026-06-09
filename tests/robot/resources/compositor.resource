*** Settings ***
Documentation    Robot Framework keywords for visual UI testing of proton-drive.
...
...              Uses ui-test-compositor.sh deployed to the VM via SSH.
...              Every visual assertion requires compositor-confirmed window + OCR proof;
...              process-status alone is not accepted as a PASS signal.
Library          SSHLibrary
Library          OperatingSystem
Library          String
Library          Collections

*** Variables ***
${UI_TEST_SCRIPT}          scripts/ci/lib/ui-test-compositor.sh
${UI_ARTIFACT_DIR}         /tmp/pd-ui-artifacts
${COMPOSITOR_TIMEOUT}      120 seconds
${OCR_TOOLS}               scrot tesseract xdotool imagemagick
${TEST_DEPS_APK}           xvfb scrot xdotool tesseract-ocr imagemagick wmctrl
${TEST_DEPS_DEB}           xvfb scrot xdotool tesseract-ocr imagemagick wmctrl x11-utils
${TEST_DEPS_RPM_DNF}       xorg-x11-server-Xvfb scrot xdotool tesseract imagemagick wmctrl xorg-x11-utils
${TEST_DEPS_RPM_ZYPPER}    xvfb-run scrot xdotool tesseract-ocr imagemagick wmctrl xorg-x11-utils
${TEST_DEPS_AUR}           xorg-server-xvfb scrot xdotool tesseract imagemagick wmctrl xorg-xwininfo

*** Keywords ***

# ── Compositor test dep install ───────────────────────────────────────────────

Install Visual Test Dependencies
    [Documentation]    Install screenshot + OCR + xdotool tools on VM for visual testing.
    [Arguments]    ${family}
    ${cmd}=    Set Variable If
    ...    '${family}' == 'apk'
    ...       apk add --no-cache ${TEST_DEPS_APK} python3 py3-pip 2>/dev/null || true
    ...    '${family}' == 'deb'
    ...       DEBIAN_FRONTEND=noninteractive apt-get install -y -q ${TEST_DEPS_DEB} python3-pip 2>/dev/null || true
    ...    '${family}' == 'rpm-dnf'
    ...       dnf install -y ${TEST_DEPS_RPM_DNF} python3-pip 2>/dev/null || true
    ...    '${family}' == 'rpm-zypper'
    ...       zypper --non-interactive install ${TEST_DEPS_RPM_ZYPPER} python3-pip 2>/dev/null || true
    ...    '${family}' == 'aur'
    ...       pacman -S --noconfirm --needed ${TEST_DEPS_AUR} python-pip 2>/dev/null || true
    Execute Command    ${cmd}
    # pyotp for TOTP 2FA generation
    Execute Command    pip3 install --quiet pyotp 2>/dev/null || true

# ── Deploy compositor test script to VM ───────────────────────────────────────

Deploy UI Test Script
    [Documentation]    Copy ui-test-compositor.sh to the VM.
    Put File    ${UI_TEST_SCRIPT}    /tmp/pd-ui-test.sh
    Execute Command    chmod +x /tmp/pd-ui-test.sh

# ── Run a test suite via compositor ──────────────────────────────────────────

Run Compositor Suite
    [Documentation]    Run a named suite on the VM; return (stdout, rc).
    [Arguments]    ${suite}    ${artifact_dir}=${UI_ARTIFACT_DIR}
    Execute Command    mkdir -p ${artifact_dir}
    ${out}    ${rc}=    Execute Command
    ...    bash /tmp/pd-ui-test.sh ${suite} ${artifact_dir} 2>&1
    ...    return_stdout=True    return_rc=True
    Log    ${out}
    RETURN    ${out}    ${rc}

Compositor Suite Should Pass
    [Documentation]    Run a suite and fail the test if any assertion inside failed.
    [Arguments]    ${suite}    ${artifact_dir}=${UI_ARTIFACT_DIR}
    ${out}    ${rc}=    Run Compositor Suite    ${suite}    ${artifact_dir}
    Log    ${out}
    Should Be Equal As Integers    ${rc}    0
    ...    Suite '${suite}' had failures:\n${out}

# ── Screenshot retrieval ──────────────────────────────────────────────────────

Fetch Screenshots From VM
    [Documentation]    scp all screenshots from the VM back to the runner for CI artifacts.
    [Arguments]    ${local_dir}    ${remote_dir}=${UI_ARTIFACT_DIR}
    ${out}=    Execute Command    ls ${remote_dir}/*.png 2>/dev/null || echo NONE
    Run Keyword If    '${out}' != 'NONE'
    ...    Get Directory    ${remote_dir}    ${local_dir}

# ── OCR assertion keywords ────────────────────────────────────────────────────

Screen Should Contain
    [Documentation]    OCR-verify the current screen shows expected text (case-insensitive).
    [Arguments]    ${expected_text}    ${label}=ocr_check
    ${out}=    Execute Command
    ...    scrot -z /tmp/pd-ui-artifacts/${label}.png 2>/dev/null;
    ...    tesseract /tmp/pd-ui-artifacts/${label}.png stdout -l eng --psm 3 2>/dev/null
    ...    || echo NOTESSERACT
    ${lower}=    Convert To Lower Case    ${out}
    ${exp_lower}=    Convert To Lower Case    ${expected_text}
    Should Contain    ${lower}    ${exp_lower}
    ...    Screen did not contain '${expected_text}' — OCR output: ${out}

Screen Should Not Contain
    [Documentation]    OCR-verify text does NOT appear on screen.
    [Arguments]    ${unexpected_text}    ${label}=ocr_neg
    ${out}=    Execute Command
    ...    scrot -z /tmp/pd-ui-artifacts/${label}.png 2>/dev/null;
    ...    tesseract /tmp/pd-ui-artifacts/${label}.png stdout -l eng --psm 3 2>/dev/null
    ...    || echo NOTESSERACT
    ${lower}=    Convert To Lower Case    ${out}
    ${exp_lower}=    Convert To Lower Case    ${unexpected_text}
    Should Not Contain    ${lower}    ${exp_lower}
    ...    Unexpected text '${unexpected_text}' found on screen — OCR output: ${out}
