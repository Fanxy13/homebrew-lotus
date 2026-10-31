# Lotus tests on Debian 12 – build from the repository root:  docker build -f tests/docker/debian.Dockerfile -t lotus-test:debian .
FROM debian:12
ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
RUN apt-get update && apt-get install -y --no-install-recommends \
      zsh bash python3 python3-venv curl git jq ca-certificates locales procps util-linux xxd file perl \
      imagemagick ffmpeg bubblewrap playerctl xclip wl-clipboard libnotify-bin libsecret-tools unzip sudo \
      openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*
COPY data/vendor.tsv /tmp/vendor.tsv
RUN set -e; case $(uname -m) in aarch64) p=linux-aarch64;; *) p=linux-amd64;; esac; \
    line=$(awk -F'\t' -v p=$p '$1=="fastfetch" && $3==p {print}' /tmp/vendor.tsv); \
    curl -fsSL -o /tmp/ff.tgz "$(echo "$line" | cut -f4)"; echo "$(echo "$line" | cut -f5)  /tmp/ff.tgz" | sha256sum -c -; \
    tar -xzf /tmp/ff.tgz -C /tmp; install -m755 /tmp/fastfetch-*/usr/bin/fastfetch /usr/local/bin/fastfetch; rm -rf /tmp/ff.tgz /tmp/fastfetch-* /tmp/vendor.tsv
RUN useradd -m -s /bin/bash tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /lotus
