#!/usr/bin/bash
# Compila os módulos ov02c10 e MAX98390 contra o kernel exato do Bazzite e
# empacota o resultado em um RPM (galaxybook-bazzite-kmods) em /out.
set -euxo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION precisa ser informado}"

REPO_FILE_URL="https://packages.caioregis.com/fedora/caioregis.repo"
KMODS=(galaxybook-ov02c10 galaxybook-max98390)

dnf5 -y install dnf5-plugins akmods rpm-build openssl kmod cpio gcc make elfutils-libelf-devel dwarves

### kernel-devel do Bazzite (vem da imagem ghcr.io/ublue-os/akmods)
if [[ ! -f "/tmp/kernel-rpms/kernel-devel-${KERNEL_VERSION}.rpm" ]]; then
    echo "kernel-devel-${KERNEL_VERSION}.rpm não encontrado. Conteúdo disponível:" >&2
    ls -1 /tmp/kernel-rpms >&2
    exit 1
fi
dnf5 -y install --setopt=install_weak_deps=False "/tmp/kernel-rpms/kernel-devel-${KERNEL_VERSION}.rpm"
test -d "/usr/src/kernels/${KERNEL_VERSION}"

### Chave de assinatura para Secure Boot (opcional)
SIGNED=0
if [[ -s /run/secrets/mok_key && -s /run/secrets/mok_cert ]]; then
    install -Dm600 /run/secrets/mok_key /etc/pki/akmods/private/private_key.priv
    if grep -q "BEGIN CERTIFICATE" /run/secrets/mok_cert; then
        mkdir -p /etc/pki/akmods/certs
        openssl x509 -in /run/secrets/mok_cert -outform DER -out /etc/pki/akmods/certs/public_key.der
    else
        install -Dm644 /run/secrets/mok_cert /etc/pki/akmods/certs/public_key.der
    fi
    SIGNED=1
else
    echo "AVISO: nenhuma chave MOK informada; os módulos NÃO serão assinados." >&2
    echo "AVISO: com Secure Boot ativo o kernel vai recusar ov02c10 e MAX98390." >&2
    rm -rf /etc/pki/akmods/private /etc/pki/akmods/certs
fi

### Código-fonte dos drivers, tirado dos pacotes akmod do repositório dedicado.
### Os módulos são compilados direto com make (como o próprio Galaxy Book Setup
### faz para o MAX98390): o spec do akmod-galaxybook-max98390 não compila nada
### quando rodado pelo akmods, e o akmods não serve fora de um sistema em boot.
dnf5 -y config-manager addrepo --from-repofile="${REPO_FILE_URL}"
dnf5 -y install --setopt=install_weak_deps=False "${KMODS[@]/#/akmod-}"

KDIR="/usr/src/kernels/${KERNEL_VERSION}"
STAGING=/tmp/kmod-staging
MODDIR="${STAGING}/usr/lib/modules/${KERNEL_VERSION}/extra"

# $1 = kmod, $2 = destino relativo a extra/, $3.. = módulos .ko
build_kmod() {
    local kmod="$1" dest="$2"; shift 2
    local work="/tmp/src-${kmod}" srpm archive srcdir
    srpm="$(readlink -f "/usr/src/akmods/${kmod}-kmod.latest")"
    mkdir -p "${work}"
    (cd "${work}" && rpm2cpio "${srpm}" | cpio -idm --quiet)
    archive="$(find "${work}" -maxdepth 1 -name "${kmod}-kmod-*.tar.gz" | head -n1)"
    tar -C "${work}" -xf "${archive}"
    srcdir="$(find "${work}" -maxdepth 1 -mindepth 1 -type d -name "${kmod}-kmod-*" | head -n1)"

    make -C "${KDIR}" M="${srcdir}/module" modules

    mkdir -p "${MODDIR}/${dest}"
    for mod in "$@"; do
        if [[ ${SIGNED} -eq 1 ]]; then
            "${KDIR}/scripts/sign-file" sha256 \
                /etc/pki/akmods/private/private_key.priv \
                /etc/pki/akmods/certs/public_key.der \
                "${srcdir}/module/${mod}.ko"
        fi
        install -m0644 "${srcdir}/module/${mod}.ko" "${MODDIR}/${dest}/${mod}.ko"
    done
}

# Mesmos caminhos dos pacotes kmod oficiais (o Galaxy Book Setup confere extra/galaxybook-ov02c10)
build_kmod galaxybook-ov02c10 galaxybook-ov02c10/drivers/media/i2c ov02c10
build_kmod galaxybook-max98390 galaxybook-max98390/sound/hda/codecs/side-codecs \
    snd-hda-scodec-max98390 snd-hda-scodec-max98390-i2c

### Confere os módulos gerados
for mod in ov02c10 snd-hda-scodec-max98390 snd-hda-scodec-max98390-i2c; do
    path=$(find "${STAGING}" -name "${mod}.ko" | head -n1)
    if [[ -z "${path}" ]]; then
        echo "Módulo ${mod} não foi gerado" >&2
        exit 1
    fi
    modinfo "${path}"
    if [[ "$(modinfo -F vermagic "${path}")" != "${KERNEL_VERSION} "* ]]; then
        echo "Módulo ${mod} não foi compilado para ${KERNEL_VERSION}" >&2
        exit 1
    fi
    if [[ ${SIGNED} -eq 1 ]] && [[ -z "$(modinfo -F signer "${path}")" ]]; then
        echo "Módulo ${mod} não está assinado apesar da chave MOK" >&2
        exit 1
    fi
done

# Só os .ko entram no RPM final; o restante vem dos pacotes *-kmod-common
(cd "${STAGING}" && find . -name '*.ko*' -type f | sed 's|^\.||') > /tmp/kmod-files.txt
cat /tmp/kmod-files.txt

### Empacota os módulos compilados em um RPM que também satisfaz as
### dependências de akmod-* dos apps (galaxybook-camera exige o akmod).
ver() { rpm -q --qf '%{VERSION}-%{RELEASE}' "akmod-$1"; }
mkdir -p /out/rpms
rpmbuild -bb /ctx/galaxybook-bazzite-kmods.spec \
    --define "_topdir /tmp/rpmbuild" \
    --define "staging ${STAGING}" \
    --define "filelist /tmp/kmod-files.txt" \
    --define "kernel_version ${KERNEL_VERSION}" \
    --define "ov02c10_evr $(ver galaxybook-ov02c10)" \
    --define "max98390_evr $(ver galaxybook-max98390)"
find /tmp/rpmbuild/RPMS -name '*.rpm' -exec cp -v {} /out/rpms/ \;

if [[ ${SIGNED} -eq 1 ]]; then
    install -Dm644 /etc/pki/akmods/certs/public_key.der /out/galaxybook-mok.der
fi
