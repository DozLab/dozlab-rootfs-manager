ARG TAG=test
FROM dozman99/lab-base_image:${TAG}
# Create the following files, but unset them
RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id

# This container image doesn't have locales installed. Disable forwarding the
# user locale env variables or we get warnings such as:
#  bash: warning: setlocale: LC_ALL: cannot change locale
RUN sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config

RUN mkdir -m 0700 -p /root/.ssh

# Set the root password to root when logging in through the VM's ttyS0 console
RUN echo "root:root" | chpasswd