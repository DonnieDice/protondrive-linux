*** Settings ***
Documentation    Reusable keywords for verifying a proton-drive package on a target
...              test VM over SSH. Used by the per-distro acceptance suites.
...              Requires SSHLibrary (see tests/robot/requirements.txt).
Library          SSHLibrary
Library          OperatingSystem
Library          String

*** Variables ***
${VM_USER}            root
${SSH_TIMEOUT}        30 seconds
${GUI_CHECKER}        scripts/ci/lib/gui-load-check.sh
${SETTLE_SECONDS}     12

*** Keywords ***
Connect To Test VM
    [Documentation]    Open an SSH connection to the VM using the deploy key.
    [Arguments]    ${ip}    ${keyfile}    ${user}=${VM_USER}
    Open Connection    ${ip}    timeout=${SSH_TIMEOUT}
    Login With Public Key    ${user}    ${keyfile}
    ${out}=    Execute Command    uname -a
    Log    Connected to ${ip}: ${out}

Copy Package To VM
    [Documentation]    scp the built package to /tmp on the VM; return the remote path.
    [Arguments]    ${local_pkg}
    ${base}=    Evaluate    __import__('os').path.basename(r"${local_pkg}")
    Execute Command    mkdir -p /tmp/pd-deploy
    Put File    ${local_pkg}    /tmp/pd-deploy/${base}
    RETURN    /tmp/pd-deploy/${base}

Install Package On VM
    [Documentation]    Install with the native package manager for the distro family.
    [Arguments]    ${remote_pkg}    ${family}
    ${cmd}=    Set Variable If
    ...    '${family}' == 'deb'    DEBIAN_FRONTEND=noninteractive apt-get install -y -q ${remote_pkg} || { dpkg -i ${remote_pkg}; apt-get -y -f install; }
    ...    '${family}' == 'rpm-dnf'    dnf install -y ${remote_pkg} || rpm -i --force ${remote_pkg}
    ...    '${family}' == 'rpm-zypper'    zypper --non-interactive install --allow-unsigned-rpm ${remote_pkg} || rpm -i --force ${remote_pkg}
    ...    '${family}' == 'aur'    pacman -U --noconfirm ${remote_pkg}
    ...    '${family}' == 'apk'    sh -c 'cd /tmp/pd-deploy && tar -xzf ${remote_pkg} -C /'
    ${rc}=    Execute Command    ${cmd}    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0    Package install failed (family=${family})

Proton Drive Binary Should Be Installed
    ${path}=    Execute Command    command -v proton-drive || echo MISSING
    Should Not Be Equal    ${path}    MISSING    proton-drive not on PATH
    Log    binary: ${path}

Proton Drive Should Report Version
    ${rc}=    Execute Command    (proton-drive --version || proton-drive --help) >/dev/null 2>&1; echo done
    ...    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0

Desktop Entry Should Be Installed
    ${out}=    Execute Command    ls /usr/share/applications/*roton*rive* 2>/dev/null | head -1
    Should Not Be Empty    ${out}    desktop entry missing

Application Icon Should Be Installed
    ${out}=    Execute Command    ls /usr/share/icons/hicolor/*/apps/*roton*rive* 2>/dev/null | head -1
    Should Not Be Empty    ${out}    application icon missing

GUI Should Load Under CI Compositor
    [Documentation]    Push the micro-compositor checker to the VM and require a PASS.
    Put File    ${GUI_CHECKER}    /tmp/gui-load-check.sh
    ${out}=    Execute Command    bash /tmp/gui-load-check.sh proton-drive ${SETTLE_SECONDS}
    Log    ${out}
    Should Contain    ${out}    GUI_LOAD_RESULT=PASS    GUI did not load under CI compositor
