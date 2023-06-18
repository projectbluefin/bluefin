FROM quay.io/fedora/fedora-coreos:stable as bluefin

COPY etc /etc
COPY usr /usr

RUN rpm-ostree install micro

RUN pip install --prefix=/usr yafti && \
    systemctl unmask dconf-update.service && \
    systemctl enable dconf-update.service && \
    systemctl enable rpm-ostree-countme.service && \
    systemctl enable tailscaled.service && \
    fc-cache -f /usr/share/fonts/ubuntu && \
    rm -f /etc/yum.repos.d/tailscale.repo && \
    sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/user.conf && \
    sed -i 's/#DefaultTimeoutStopSec.*/DefaultTimeoutStopSec=15s/' /etc/systemd/system.conf && \
    rm -rf /tmp/* /var/* && \
    ostree container commit && \
    mkdir -p /var/tmp && \
    chmod -R 1777 /var/tmp

RUN rm -rf /tmp/* /var/*
RUN ostree container commit
