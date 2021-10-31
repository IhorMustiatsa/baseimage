FROM python:3.7-slim-buster

ENV LANG=C.UTF-8 \
    JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto
ENV PATH=$JAVA_HOME/bin:$PATH

RUN set -eux \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl jq \
        ca-certificates \
        p11-kit \
        gnupg \
        software-properties-common \
    && curl -fL https://apt.corretto.aws/corretto.key | apt-key add - \
    && add-apt-repository 'deb https://apt.corretto.aws stable main' \
    && mkdir -p /usr/share/man/man1 || true \
    && apt-get update \
    && apt-get install -y java-11-amazon-corretto-jdk \
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
        gnupg software-properties-common \
    ; \
    \
# Update "cacerts" bundle to use Debian's CA certificates and make sure they stay in sync
  { \
    echo '#!/usr/bin/env bash'; \
    echo 'set -Eeuo pipefail'; \
    echo 'if ! [ -d "$JAVA_HOME" ]; then echo >&2 "error: missing JAVA_HOME environment variable"; exit 1; fi'; \
    echo 'cacertsFile=$JAVA_HOME/lib/security/cacerts'; \
    echo 'if [ -z "$cacertsFile" ] || ! [ -f "$cacertsFile" ]; then echo >&2 "error: failed to find cacerts file in $JAVA_HOME"; exit 1; fi'; \
    echo 'trust extract --overwrite --format=java-cacerts --filter=ca-anchors --purpose=server-auth "$cacertsFile"'; \
  } > /etc/ca-certificates/update.d/docker-jdk; \
  chmod +x /etc/ca-certificates/update.d/docker-jdk; \
  /etc/ca-certificates/update.d/docker-jdk; \
  \
# Basic smoke test
  javac --version; \
  java --version

#
# Install AWS CLI & cleanup apt
#
RUN set -eu; \
  pip3 install awscli

#
# Install Docker client
#
ENV DOCKER_CHANNEL=stable \
    DOCKER_VERSION=19.03.13

RUN set -eu; \
  savedAptMark="$(apt-mark showmanual)"; \
  apt-get update; \
  apt-get install -y \
    wget \
  ; \
  \
# Download and extract Docker
  dpkgArch="$(dpkg --print-architecture)"; \
  case "$dpkgArch" in \
	amd64) dockerArch='x86_64' ;; \
	*) echo >&2 "error: unsupported architecture: $dpkgArch" ;; \
  esac; \
  \
  if ! wget -O docker.tgz "https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${dockerArch}/docker-${DOCKER_VERSION}.tgz"; then \
    echo >&2 "error: failed to download 'docker-${DOCKER_VERSION}' from '${DOCKER_CHANNEL}' for '${dockerArch}'"; \
	exit 1; \
  fi; \
  tar --extract \
	  --file docker.tgz \
	  --strip-components 1 \
	  --directory /usr/local/bin/ \
  ; \
  rm docker.tgz; \
  \
# Cleanup packages required to pull Docker
  apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  \
# Smoke test
  dockerd --version; \
  docker --version

ENV AWS_DEFAULT_REGION="eu-central-1" \
    GRADLE_USER_HOME=".gradle"

COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN set -eu; \
  chmod 0755 /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

