FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf automake build-essential cmake git-core \
    libass-dev libfreetype6-dev libsdl2-dev libtool \
    libva-dev libvdpau-dev libvorbis-dev libxcb1-dev \
    libxcb-shm0-dev libxcb-xfixes0-dev pkg-config texinfo \
    wget zlib1g-dev libunistring-dev \
    libx264-dev libx265-dev libnuma-dev \
    libfdk-aac-dev libmp3lame-dev libopus-dev \
    libssl-dev libass-dev \
    yasm nasm \
    python3 python3-pip python3-yaml \
    nvidia-cuda-toolkit \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Optional: Don't overwrite custom ffmpeg build
ARG SKIP_FFMPEG_BUILD=false

WORKDIR /opt

# Clone FFmpeg source only if build is needed
RUN if [ "$SKIP_FFMPEG_BUILD" = "false" ]; then \
      git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg; \
    fi

# Build FFmpeg with NVIDIA + SSL if needed
RUN if [ "$SKIP_FFMPEG_BUILD" = "false" ]; then \
      cd /opt/ffmpeg && \
      ./configure \
        --prefix=/usr/local \
        --enable-gpl \
        --enable-nonfree \
        --enable-cuda \
        --enable-cuvid \
        --enable-nvenc \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libfdk-aac \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-openssl \
        --enable-protocol=https \
        --enable-libass \
        --enable-shared && \
      make -j$(nproc) && \
      make install && \
      ldconfig; \
    fi

# App layer (optional if using with your Flask app)
WORKDIR /app
COPY . /app
RUN pip3 install --no-cache-dir flask pyyaml

EXPOSE 3037
CMD ["python3", "app.py"]
