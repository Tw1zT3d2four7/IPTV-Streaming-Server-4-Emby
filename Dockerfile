FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /opt

# Install system dependencies
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
    python3 python3-pip \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Get NVENC SDK headers
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make -j$(nproc) && make install && \
    ldconfig

# Clone FFmpeg source
RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg

# Build FFmpeg with CUDA/NVENC + OpenSSL
WORKDIR /opt/ffmpeg
RUN ./configure \
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
    ldconfig

# App layer (optional)
WORKDIR /app
COPY . /app
RUN pip3 install flask
EXPOSE 3037

CMD ["python3", "app.py"]
