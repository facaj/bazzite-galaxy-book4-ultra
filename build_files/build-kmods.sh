#!/usr/bin/bash
# Compila os módulos ov02c10 e MAX98390 contra o kernel exato do Bazzite e
# empacota o resultado em um RPM (galaxybook-bazzite-kmods) em /out.
set -euxo pipefail

: "${KERNEL_VERSION:?KERNEL_VERSION precisa ser informado}"

REPO_FILE_URL="https://packages.caioregis.com/fedora/caioregis.repo"
KMODS=(galaxybook-ov02c10 galaxybook-max98390)

dnf5 -y install dnf5-plugins akmods rpm-build openssl kmod cpio

### Kernel do Bazzite + kernel-devel (vêm da imagem ghcr.io/ublue-os/akmods).
### O kernel inteiro é instalado só neste estágio descartável, porque o RPM
### gerado pelo akmods exige kernel-uname-r = ${KERNEL_VERSION}.
if [[ ! -f "/tmp/kernel-rpms/kernel-devel-${KERNEL_VERSION}.rpm" ]]; then
    echo "kernel-devel-${KERNEL_VERSION}.rpm não encontrado. Conteúdo disponível:" >&2
    ls -1 /tmp/kernel-rpms >&2
    exit 1
fi
mapfile -t kernel_rpms < <(find /tmp/kernel-rpms -maxdepth 1 -name "*-${KERNEL_VERSION}.rpm" ! -name '*uki*')
# noscripts: o kernel não vai dar boot aqui; evita rodar kernel-install/dracut
dnf5 -y install --setopt=install_weak_deps=False --setopt=tsflags=noscripts "${kernel_rpms[@]}"
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

### akmods do repositório dedicado
dnf5 -y config-manager addrepo --from-repofile="${REPO_FILE_URL}"
dnf5 -y install --setopt=install_weak_deps=False "${KMODS[@]/#/akmod-}"

# O akmods retorna 0 mesmo quando o build falha, então o resultado é conferido
# pelo RPM gerado em /var/cache/akmods, e não pelo código de saída.
STAGING=/tmp/kmod-staging
mkdir -p "${STAGING}"
failed=()
for kmod in "${KMODS[@]}"; do
    akmods --force --kernels "${KERNEL_VERSION}" --kmod "${kmod}" || true
    rpmfile=$(find "/var/cache/akmods/${kmod}" -name "*-for-${KERNEL_VERSION}.rpm" 2>/dev/null | head -n1)
    if [[ -z "${rpmfile}" ]]; then
        echo "::error::${kmod} não compilou para ${KERNEL_VERSION}" >&2
        find "/var/cache/akmods/${kmod}" -name '*.log' -print -exec cat {} \; >&2 || true
        failed+=("${kmod}")
        continue
    fi
    echo "RPM gerado: ${rpmfile}"
    rpm -qlp "${rpmfile}"
    (cd "${STAGING}" && rpm2cpio "${rpmfile}" | cpio -idm --quiet)
done
if [[ ${#failed[@]} -gt 0 ]]; then
    echo "Falha ao compilar: ${failed[*]} (log acima)" >&2
    exit 1
fi

# Normaliza /lib/modules -> /usr/lib/modules (no Bazzite /lib é symlink)
if [[ -d "${STAGING}/lib" ]]; then
    mkdir -p "${STAGING}/usr"
    cp -a "${STAGING}/lib" "${STAGING}/usr/"
    rm -rf "${STAGING:?}/lib"
fi

### Confere se os módulos esperados saíram do build
for mod in ov02c10 snd-hda-scodec-max98390 snd-hda-scodec-max98390-i2c; do
    path=$(find "${STAGING}" -name "${mod}.ko*" | head -n1)
    if [[ -z "${path}" ]]; then
        echo "Módulo ${mod} não está nos RPMs gerados pelo akmods" >&2
        find "${STAGING}" -type f >&2
        exit 1
    fi
    modinfo "${path}"
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
