# COPR isolation invariant

Keep the package helper's sequence intact:

1. Enable the COPR.
2. Disable it globally.
3. Install only with an explicit repository selector.

The disable step is a security boundary, not cleanup. It prevents a third-party
repository from remaining active for later package transactions.

Read `build_files/shared/copr-helpers.sh` before changing the sequence.
