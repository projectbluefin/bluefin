#!/usr/bin/env bats
# Regression guard for the AMD s2idle / s0ix wakeup workaround (bluefin#383).
#
# projectbluefin/common owns the single valid userspace mitigation,
# usr/lib/udev/rules.d/60-amd-s2idle-fixes.rules, which clears power/wakeup on
# the i8042 keyboard port (serio0 / atkbd). Bluefin must not ship a second rule
# extending that to the i8042 AUX port (serio1 / psmouse): such a rule writes
# "disabled" over a value that is already "disabled" on every machine, so it
# cannot change sleep power draw. Three facts from the kernel pin this down.
#
#   1. drivers/input/serio/i8042.c, i8042_start() — wakeup is enabled by
#      default only for i8042_ports[I8042_KBD_PORT_NO]. The AUX port is made
#      wakeup-*capable* but never wakeup-*enabled*.
#   2. drivers/input/serio/i8042.c, i8042_pm_suspend() — enable_irq_wake() is
#      called only for ports where device_may_wakeup() is true, so the AUX port
#      never arms an IRQ wake source in the first place.
#   3. drivers/platform/x86/amd/pmc/pmc.c, amd_pmc_wa_irq1() — the
#      quirk_s2idle_spurious_8042 quirk that this workaround mirrors resolves
#      "serio0" by name and touches nothing else.
#
# I8042_KBD_PORT_NO is 0, I8042_AUX_PORT_NO is 1, and i8042_register_ports()
# registers in index order, so serio0 is the keyboard and serio1 is the mouse.
#
# Run with: bats tests/unit/amd-s2idle-udev_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
SYSTEM_FILES="${SCRIPT_DIR}/../../system_files"

@test "amd-s2idle: system_files exists" {
    [ -d "${SYSTEM_FILES}" ]
}

@test "amd-s2idle: no shipped file references psmouse" {
    # A psmouse wakeup assignment is a no-op by construction (see header). If
    # one reappears, the mitigation it claims to provide is not real.
    run grep -rIl "psmouse" "${SYSTEM_FILES}"

    [ -z "$output" ]
}

@test "amd-s2idle: no shipped udev rule matches the serio subsystem" {
    # common owns every serio wakeup rule. A second copy here drifts from it
    # silently and has to be found in two repositories when the upstream
    # pmc-quirks.c entry for board 8D01 lands and the workaround is retired.
    run grep -rIl 'SUBSYSTEM=="serio"' "${SYSTEM_FILES}"

    [ -z "$output" ]
}

@test "amd-s2idle: no shipped file forks common's amd-s2idle rules" {
    run find "${SYSTEM_FILES}" -name "*amd-s2idle*"

    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
