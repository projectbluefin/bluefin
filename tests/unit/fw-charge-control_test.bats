#!/usr/bin/env bats
# Unit tests for system_files/shared/usr/lib/modprobe.d/fw-charge-control.conf
# (bluefin#879 — Framework battery charge threshold control via cros_charge-control)
# Run with: bats tests/unit/fw-charge-control_test.bats

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/../../system_files/shared/usr/lib/modprobe.d/fw-charge-control.conf"

@test "fw-charge-control.conf is shipped in the image" {
    [ -f "${CONF_FILE}" ]
}

@test "fw-charge-control.conf enables Framework probing for cros_charge-control" {
    # The cros_charge-control kernel driver (v6.14+, built by Fedora as
    # CONFIG_CHARGER_CROS_CONTROL=m) intentionally refuses Framework ECs unless
    # probe_with_fwk_charge_control=1 is set. Without this option, AMD Framework
    # systems have no charge_control_end_threshold sysfs node, so the Battery
    # Health Charging extension reports missing dependencies (bluefin#879).
    grep -q "^options cros_charge_control probe_with_fwk_charge_control=1$" "${CONF_FILE}"
}

@test "fw-charge-control.conf contains exactly one option line" {
    # Keep the file auditable: one module, one option, nothing else.
    run grep -c "^options " "${CONF_FILE}"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}
