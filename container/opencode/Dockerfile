FROM ghcr.io/anomalyco/opencode@sha256:812493bdbfb3dc8c54b83c5095980c846ad58a60953ecc2dd2ad455e1dd0ff77

RUN apk add --no-cache \
  bash \
  ca-certificates \
  curl \
  git \
  openssh-client \
  jq \
  less \
  file \
  patch \
  diffutils \
  findutils \
  tar \
  gzip \
  xz \
  unzip \
  openssl

COPY container-entrypoint.sh /usr/local/bin/container-entrypoint.sh
RUN chmod 0755 /usr/local/bin/container-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
