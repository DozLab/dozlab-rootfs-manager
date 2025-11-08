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