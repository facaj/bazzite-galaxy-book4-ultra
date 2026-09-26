# Imagem Bazzite com o suporte ao Samsung Galaxy Book4 Ultra embutido.
#
# O Bazzite é um sistema imutável (bootc/rpm-ostree): /usr é somente leitura e
# o akmods não consegue compilar módulos no boot, porque o kernel do Bazzite
# (flavor "ogc") não tem kernel-devel nos repositórios do Fedora. Por isso os
# módulos ov02c10 e MAX98390 são compilados aqui, na hora do build, contra o
# kernel exato da imagem base, e entram prontos na imagem final.
#
# Build local:   ./scripts/build-local.sh
# Build na nuvem: .github/workflows/build.yml

ARG BASE_IMAGE="ghcr.io/ublue-os/bazzite-nvidia-open:stable"
# Versão exata do kernel da imagem base (ex.: 7.1.4-ogc1.1.fc44.x86_64).
# Os scripts de build descobrem esse valor automaticamente.
ARG KERNEL_VERSION
ARG KERNEL_FLAVOR="ogc"
ARG FEDORA_VERSION="44"

# kernel-devel correspondente ao kernel do Bazzite, publicado pelo Universal Blue
FROM ghcr.io/ublue-os/akmods:${KERNEL_FLAVOR}-${FEDORA_VERSION}-${KERNEL_VERSION} AS akmods

FROM scratch AS ctx
COPY build_files /

###############################################################################
# Estágio de compilação dos módulos (não vai para a imagem final)
###############################################################################
FROM quay.io/fedora/fedora:${FEDORA_VERSION} AS kmods

ARG KERNEL_VERSION

RUN --mount=type=bind,from=akmods,src=/kernel-rpms,dst=/tmp/kernel-rpms \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=secret,id=mok_key \
    --mount=type=secret,id=mok_cert \
    KERNEL_VERSION="${KERNEL_VERSION}" /ctx/build-kmods.sh

###############################################################################
# Imagem final
###############################################################################
FROM ${BASE_IMAGE}

ARG KERNEL_VERSION

COPY system_files/ /

RUN --mount=type=bind,from=kmods,src=/out,dst=/tmp/kmods \
    --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    KERNEL_VERSION="${KERNEL_VERSION}" /ctx/install.sh

RUN bootc container lint
