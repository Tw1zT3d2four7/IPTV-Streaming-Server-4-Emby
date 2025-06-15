FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Install build dependencies
RUN apt-get update && apt-get install -y \
  autoconf automake build-essential cmake git-core libass-dev \
  libfreetype6-dev libsdl2-dev libtool libva-dev libvdpau-dev \
  libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev \
  pkg-config texinfo wget zlib1g-dev libunistring-dev \
  libx264-dev libx265-dev libnuma-dev libfdk-aac-dev \
  libmp3lame-dev libopus-dev libssl-dev \
  python3 python3-pip python3-yaml \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Clone and build FFmpeg
WORKDIR /opt
RUN git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg && \
    cd ffmpeg && \
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
      --enable-openssl \
      --enable-protocol=https \
      --enable-libopus \
      --enable-libass \
      --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Create app directory
WORKDIR /app

# Copy your app files
COPY . /app

# Install Python dependencies
RUN pip3 install flask pyyaml

# Expose Flask port
EXPOSE 3037

# Start the app
CMD ["python3", "app.py"]
