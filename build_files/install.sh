#!/usr/bin/bash
# Instala o suporte ao Galaxy Book4 Ultra na imagem Bazzite final.
set -euxo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION precisa ser informado}"

REPO_FILE_URL="https://packages.caioregis.com/fedora/caioregis.repo"

# A imagem precisa ter exatamente o kernel usado para compilar os módulos
if [[ ! -d "/usr/lib/modules/${KERNEL_VERSION}" ]]; then
    echo "A imagem base não tem o kernel ${KERNEL_VERSION}:" >&2
    ls -1 /usr/lib/modules >&2
    exit 1
fi

dnf5 -y config-manager addrepo --overwrite --from-repofile="${REPO_FILE_URL}"

# install_weak_deps=False evita que o dnf puxe akmods/kernel-devel do Fedora,
# que não funcionam no kernel do Bazzite.
dnf5 -y install --setopt=install_weak_deps=False \
    /tmp/kmods/rpms/*.rpm \
    galaxybook-ov02c10-kmod-common \
    galaxybook-max98390-kmod-common \
    galaxybook-camera \
    galaxybook-setup \
    galaxybook-sound \
    libcamera-tools \
    libcamera-ipa \
    libcamera-v4l2 \
    pipewire-plugin-libcamera \
    i2c-tools \
    v4l-utils

# O repositório fica desativado: no Bazzite as atualizações chegam pela imagem
# (rpm-ostree/bootc upgrade), não por dnf/rpm-ostree install.
shopt -s nullglob
for repo in /etc/yum.repos.d/caioregis*.repo; do
    sed -i 's/^enabled=.*/enabled=0/' "${repo}"
done

depmod -a "${KERNEL_VERSION}"
modinfo -k "${KERNEL_VERSION}" -n ov02c10
modinfo -k "${KERNEL_VERSION}" -n snd-hda-scodec-max98390
modinfo -k "${KERNEL_VERSION}" -n snd-hda-scodec-max98390-i2c

# Chave pública usada para assinar os módulos (Secure Boot).
# Fica no caminho que o Galaxy Book Setup já verifica.
if [[ -s /tmp/kmods/galaxybook-mok.der ]]; then
    install -Dm644 /tmp/kmods/galaxybook-mok.der /usr/share/galaxybook-bazzite/galaxybook-mok.der
    install -Dm644 /tmp/kmods/galaxybook-mok.der /etc/pki/akmods/certs/public_key.der
fi

systemctl enable max98390-hda-i2c-setup.service

rm -rf /var/lib/dnf /var/cache/dnf /var/log/dnf5.log
