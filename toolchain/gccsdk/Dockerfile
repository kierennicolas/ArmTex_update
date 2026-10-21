# Toolchain image: the GCCSDK cross compiler plus the host tools that the
# build, packaging and check scripts need.
#
# Built by .github/workflows/toolchain.yml from a tarball produced by
# scripts/build-toolchain.sh on an Ubuntu 24.04 runner. The base image must be
# the same Ubuntu release, because the cross compiler links against the host
# C and C++ runtime libraries.

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG GCCSDK_REVISION=unknown
ARG GCCSDK_PREFIX=/opt/riscos-gccsdk/arm-unknown-riscos

# build-essential provides the host C and C++ compilers: a TeX Live cross
# build compiles helper programs for the build machine, and
# scripts/build-host-tools.sh builds tangle and friends natively. zstd lets
# actions/cache compress quickly inside the container.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      binutils \
      build-essential \
      ca-certificates \
      file \
      git \
      jq \
      make \
      python3 \
      unzip \
      xz-utils \
      zip \
      zstd \
 && rm -rf /var/lib/apt/lists/*

# The tarball holds the toolchain at its absolute install prefix.
ADD gccsdk-toolchain.tar.xz /

ENV GCCSDK_PREFIX=${GCCSDK_PREFIX} \
    GCCSDK_INSTALL_CROSSBIN=${GCCSDK_PREFIX}/cross/bin \
    GCCSDK_INSTALL_ENV=${GCCSDK_PREFIX}/env \
    PATH=${GCCSDK_PREFIX}/cross/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.source="https://github.com/kierennicolas/ArmTex_update" \
      org.opencontainers.image.description="GCCSDK cross toolchain for TeX Live for RISC OS" \
      io.github.kierennicolas.gccsdk.revision="${GCCSDK_REVISION}"
