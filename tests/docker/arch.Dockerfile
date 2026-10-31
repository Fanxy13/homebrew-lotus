# Lotus tests on Arch Linux (x86_64, through Rosetta on an Apple silicon Mac) – build from the repository root:
#   docker build --platform linux/amd64 -f tests/docker/arch.Dockerfile -t lotus-test:arch .
FROM archlinux:latest
ENV LANG=C.UTF-8
# pacman's download sandbox needs a syscall that emulation does not offer
RUN sed -i 's/^\[options\]/[options]\nDisableSandbox/' /etc/pacman.conf && pacman -Syu --noconfirm --needed \
      zsh bash python curl git jq ca-certificates procps-ng util-linux vim file perl \
      imagemagick ffmpeg bubblewrap playerctl xclip wl-clipboard libnotify libsecret unzip zip sudo \
      jre17-openjdk-headless findutils which chromium && pacman -Scc --noconfirm
COPY data/vendor.tsv /tmp/vendor.tsv
RUN set -e; line=$(awk -F'\t' '$1=="fastfetch" && $3=="linux-amd64" {print}' /tmp/vendor.tsv); \
    curl -fsSL -o /tmp/ff.tgz "$(echo "$line" | cut -f4)"; echo "$(echo "$line" | cut -f5)  /tmp/ff.tgz" | sha256sum -c -; \
    tar -xzf /tmp/ff.tgz -C /tmp; install -m755 /tmp/fastfetch-*/usr/bin/fastfetch /usr/local/bin/fastfetch; rm -rf /tmp/ff.tgz /tmp/fastfetch-* /tmp/vendor.tsv
RUN useradd -m -s /bin/bash tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester
USER tester
WORKDIR /lotus
