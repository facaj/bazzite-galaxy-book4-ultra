#!/usr/bin/bash
# Gera a imagem localmente com podman (inclusive no próprio Bazzite).
#
#   sudo ./scripts/build-local.sh                 # KDE + NVIDIA (padrão)
#   sudo BASE_IMAGE=ghcr.io/ublue-os/bazzite-gnome-nvidia-open:stable ./scripts/build-local.sh
#
# Para assinar os módulos (Secure Boot), gere a chave com
# ./scripts/generate-mok-key.sh; os arquivos em certs/ são usados
# automaticamente se existirem.
set -euo pipefail

cd "$(dirname "$0")/.."

BASE_IMAGE="${BASE_IMAGE:-ghcr.io/ublue-os/bazzite-nvidia-open:stable}"
IMAGE_NAME="${IMAGE_NAME:-localhost/bazzite-galaxy-book4-ultra:latest}"
KERNEL_FLAVOR="${KERNEL_FLAVOR:-ogc}"
MOK_KEY="${MOK_KEY:-certs/galaxybook-mok.priv}"
MOK_CERT="${MOK_CERT:-certs/galaxybook-mok.der}"

podman pull "${BASE_IMAGE}"

KERNEL_VERSION="$(podman run --rm --entrypoint /usr/bin/ls "${BASE_IMAGE}" /usr/lib/modules | head -n1)"
FEDORA_VERSION="$(sed -E 's/.*\.fc([0-9]+)\..*/\1/' <<<"${KERNEL_VERSION}")"
echo "Imagem base: ${BASE_IMAGE}"
echo "Kernel:      ${KERNEL_VERSION} (Fedora ${FEDORA_VERSION}, flavor ${KERNEL_FLAVOR})"

# Os secrets são sempre passados; vazios = módulos sem assinatura.
tmp_secrets="$(mktemp -d)"
trap 'rm -rf "${tmp_secrets}"' EXIT
if [[ -s "${MOK_KEY}" && -s "${MOK_CERT}" ]]; then
    echo "Assinando módulos com ${MOK_CERT}"
    cp "${MOK_KEY}" "${tmp_secrets}/mok_key"
    cp "${MOK_CERT}" "${tmp_secrets}/mok_cert"
else
    echo "AVISO: sem chave MOK em certs/; módulos sem assinatura (desative o Secure Boot)."
    : > "${tmp_secrets}/mok_key"
    : > "${tmp_secrets}/mok_cert"
fi

podman build \
    --pull=newer \
    --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    --build-arg "KERNEL_VERSION=${KERNEL_VERSION}" \
    --build-arg "KERNEL_FLAVOR=${KERNEL_FLAVOR}" \
    --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
    --secret "id=mok_key,src=${tmp_secrets}/mok_key" \
    --secret "id=mok_cert,src=${tmp_secrets}/mok_cert" \
    --tag "${IMAGE_NAME}" \
    --file Containerfile \
    .

cat <<MSG

Imagem gerada: ${IMAGE_NAME}

Para instalar no próprio notebook (a imagem precisa estar no armazenamento
do root; rode este script com sudo ou copie com 'podman image scp'):

  sudo bootc switch --transport containers-storage ${IMAGE_NAME}
  systemctl reboot
MSG
