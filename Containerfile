FROM quay.io/fedora/fedora-coreos:stable as bluefin

COPY etc /etc
COPY usr /usr

RUN rpm-ostree install micro

RUN rm -rf /tmp/* /var/* && \
    ostree container commit && \
    mkdir -p /var/tmp && \
    chmod -R 1777 /var/tmp

RUN rm -rf /tmp/* /var/*
RUN ostree container commit
