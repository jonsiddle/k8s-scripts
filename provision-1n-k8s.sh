#!/bin/bash

ENGINE=$(whiptail --title "Choose engine" --radiolist "Select a CRI engine for k8s" 20 78 4 docker Docker off containerd containerd on 3>&1 1>&2 2>&3)

if [ "$ENGINE" == "" ] ; then
    echo "Aborting"
    exit 1
fi

ARCH=$(dpkg --print-architecture)
DISTRO=$(lsb_release -is | tr '[:upper:]' '[:lower:]')
RELEASE=$(lsb_release -cs)

echo "::: arch=$ARCH distro=$DISTRO release=$RELEASE cri-engine=$ENGINE :::"

echo "Installing base packages..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

echo "Setting system parameters..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

if [ ! -d /etc/apt/keyrings ] ; then
    echo "Older distro; creating /etc/apt/keyrings"
    sudo mkdir /etc/apt/keyrings
fi

echo "Configuring docker repository..."
curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch="$ARCH" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO "$RELEASE" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update


if [ "$ENGINE" == "docker" ] ; then
    echo "Installing docker engine..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
    sudo mkdir -p /etc/systemd/system/docker.service.d
    sudo systemctl daemon-reload
    sudo systemctl restart docker
    sudo usermod -aG docker $USER
    sudo sed -i 's/disabled_plugins = .*/disabled_plugins = []/' /etc/containerd/config.toml
    sudo service containerd restart
fi

if [ "$ENGINE" == "containerd" ] ; then
    echo "Installing containerd engine..."
    sudo apt-get install -y containerd.io
    containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
    sudo service containerd restart
fi

echo "Disabling swap..."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Configuring kubernetes repository..."
curl -fsSL https://dl.k8s.io/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [arch="$ARCH" signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
sudo apt-get update

echo "Installing k8s..."
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "Creating cluster..."
sudo kubeadm config images pull
sudo kubeadm init | tee kubeadm-init.log
mkdir ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

echo "Installing weave..."
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml
