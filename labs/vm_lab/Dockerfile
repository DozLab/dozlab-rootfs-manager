ARG TAG=test
FROM dozman99/dozlab-base:${TAG}
# Create the following files, but unset them
RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id

# This container image doesn't have locales installed. Disable forwarding the
# user locale env variables or we get warnings such as:
#  bash: warning: setlocale: LC_ALL: cannot change locale
RUN sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config

RUN mkdir -m 0700 -p /root/.ssh

# Enable passwordless login for root user (lab environment)
# Remove password requirement for root account
RUN passwd -d root && \
    # Allow passwordless login via console
    sed -i 's/nullok_secure/nullok/' /etc/pam.d/common-auth
# Networking for Firecracker: static eth0 matching start-firecracker.sh's tap/NAT layout
COPY files/10-eth0.network /etc/systemd/network/10-eth0.network

# Always run the entropy daemon: without it sshd hangs at boot on the 4.14 guest kernel
COPY files/haveged-vm.conf /etc/systemd/system/haveged.service.d/vm.conf

# Key-only root SSH (keys are injected at runtime into /root/.ssh/authorized_keys)
RUN sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config && \
    systemctl enable systemd-networkd systemd-resolved haveged ssh serial-getty@ttyS0.service
