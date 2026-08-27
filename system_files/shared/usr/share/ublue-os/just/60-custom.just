# Bluefin-specific user recipes. Imported optionally by common's 00-entry.just.

[group('System')]
runsc action="install":
    sudo /usr/libexec/bluefin-runsc "{{ action }}"
