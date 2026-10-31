# Lotus tests on Fedora 42 – build from the repository root:  docker build -f tests/docker/fedora.Dockerfile -t lotus-test:fedora .
FROM fedora:42
ENV LANG=C.UTF-8
RUN dnf -y install --setopt=install_weak_deps=False \
      zsh bash python3 python3-pip curl git jq ca-certificates procps-ng util-linux vim-common file perl \
      ImageMagick ffmpeg-free bubblewrap playerctl xclip wl-clipboard libnotify libsecret unzip zip sudo \
      java-21-openjdk-headless findutils which chromium \
    && dnf clean all
COPY data/vendor.tsv /tmp/vendor.tsv
RUN set -e; case $(uname -m) in aarch64) p=linux-aarch64;; *) p=linux-amd64;; esac; \
    line=$(awk -F'\t' -v p=$p '$1=="fastfetch" && $3==p {print}' /tmp/vendor.tsv); \
    curl -fsSL -o /tmp/ff.tgz "$(echo "$line" | cut -f4)"; echo "$(echo "$line" | cut -f5)  /tmp/ff.tgz" | sha256sum -c -; \
    tar -xzf /tmp/ff.tgz -C /tmp; install -m755 /tmp/fastfetch-*/usr/bin/fastfetch /usr/local/bin/fastfetch; rm -rf /tmp/ff.tgz /tmp/fastfetch-* /tmp/vendor.tsv
RUN useradd -m -s /bin/bash tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /lotus
