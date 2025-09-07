ARG OS_VERSION=22.04
FROM ubuntu:${OS_VERSION}

# udev is needed for booting a "real" VM, setting up the ttyS0 console properly
# kmod is needed for modprobing modules
# systemd is needed for running as PID 1 as /sbin/init
# Also, other utilities are installed
RUN apt-get update && apt-get install -y \
      curl \
      dbus \
      kmod \
      haveged \
      iproute2 \
      iputils-ping \
      net-tools \
      openssh-server \
      procps \
      rng-tools \
      sudo \
      systemd \
      udev \
      vim-tiny \
      wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
