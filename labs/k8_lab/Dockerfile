ARG TAG=test
# Built on the VM lab so it boots under Firecracker the same way: eth0 config, sshd, haveged,
# serial console and key-only root SSH all come from labs/vm_lab.
FROM dozman99/dozlab-vm:${TAG}

ARG ARCH="amd64"
ARG CONTAINERD_VERSION=1.7.19
# Kubernetes version will be used to keep the kubeadm, kubelet, and kubectl version consistent
ARG KUBERNETES_VERSION=1.30

RUN apt-get update && apt-get install -y \
        dnsutils \
        cloud-init \
        less \
        apt-transport-https \
        ca-certificates \
        gnupg2 \
        software-properties-common \
        libseccomp2 \
        jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* 




#### Let iptables see bridged traffic ###
# overlay and br_netfilter are built into the guest kernel (dozlab-infra), which has no module
# support, so nothing is listed in /etc/modules-load.d.

# Setup required sysctl params, these persist across reboots.
RUN echo "net.bridge.bridge-nf-call-iptables  = 1 \n\
net.bridge.bridge-nf-call-ip6tables = 1 \n\
net.ipv4.ip_forward                 = 1 \n\
net.ipv6.conf.all.forwarding = 1 \n\
net.ipv6.conf.all.disable_ipv6 = 0 \n\
net.ipv4.tcp_congestion_control = bbr \n\
vm.overcommit_memory = 1 \n\
kernel.panic = 10 \n\
net.ipv4.conf.all.rp_filter = 1 \n\
kernel.panic_on_oops = 1" >> /etc/sysctl.d/99-kubernetes-cri.conf

# Apply sysctl params without reboot
RUN sysctl --system

# Install Containerd
RUN wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/cri-containerd-cni-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz
RUN tar --no-overwrite-dir -C / -xzf cri-containerd-cni-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz && rm -f cri-containerd-cni-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz

### Add apt repos
# Kubeadm, Kubelet, and Kubectl
RUN sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl gpg 
RUN mkdir -p -m 755 /etc/apt/keyrings && curl -fsSL https://pkgs.k8s.io/core:/stable:/v${KUBERNETES_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 
RUN echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v'${KUBERNETES_VERSION}'/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list



RUN apt-get update && apt-get install -y \
        kubeadm\
        kubelet \
        kubectl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    apt-mark hold kubelet kubeadm kubectl

RUN kubeadm version

# kubeadm sets the kubelet to the systemd cgroup driver, so containerd must use it too
RUN mkdir -p /etc/containerd && containerd config default > /etc/containerd/config.toml && \
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml && \
    grep -q 'SystemdCgroup = true' /etc/containerd/config.toml
# Pod network: the bridge plugin from the containerd tarball (/opt/cni/bin). One node, so no
# overlay network (VXLAN) or CNI pods are needed. Matches kubeadm's --pod-network-cidr.
RUN rm /etc/cni/net.d/10-containerd-net.conflist
COPY files/10-dozlab-bridge.conflist /etc/cni/net.d/10-dozlab-bridge.conflist
RUN systemctl enable containerd


# No kubelet flags of our own: kubeadm writes the kubelet's config and runtime endpoint.
# (The old drop-in passed --container-runtime=remote, removed in Kubernetes 1.27.)
RUN systemctl enable kubelet

# First boot: kubeadm init as a single-node cluster (see files/dozlab-kubeadm-init)
COPY files/dozlab-kubeadm-init /usr/local/sbin/dozlab-kubeadm-init
COPY files/dozlab-kubeadm-init.service /etc/systemd/system/dozlab-kubeadm-init.service
RUN chmod 0755 /usr/local/sbin/dozlab-kubeadm-init && systemctl enable dozlab-kubeadm-init.service



# Package installs above may have generated one; each VM should make its own
RUN echo "" > /etc/machine-id && echo "" > /var/lib/dbus/machine-id
