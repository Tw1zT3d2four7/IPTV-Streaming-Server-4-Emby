# Base image with NVIDIA CUDA for NVENC
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Environment to suppress interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    autoconf automake build-essential cmake git-core \
    libass-dev libfreetype6-dev libsdl2-dev libtool \
    libva-dev libvdpau-dev libvorbis-dev libxcb1-dev \
    libxcb-shm0-dev libxcb-xfixes0-dev pkg-config texinfo \
    wget zlib1g-dev libunistring-dev libx264-dev libx265-dev \
    libnuma-dev libfdk-aac-dev libmp3lame-dev libopus-dev \
    libssl-dev libass-dev yasm \
    python3 python3-pip python3-yaml \
    nvidia-cuda-toolkit \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Set workdir for ffmpeg build
WORKDIR /opt

# Clone FFmpeg source (use GitHub mirror for reliability)
RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg

# Configure, build, and install FFmpeg
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
      --enable-shared \
 || { echo "FFmpeg configure failed"; tail -n 100 config.log; exit 1; }

RUN make -j$(nproc) && make install && ldconfig

# Set up Flask app directory
WORKDIR /app

# Copy application files (assuming everything is in same dir as Dockerfile)
COPY . /app

# Install Python dependencies
RUN pip3 install --no-cache-dir flask pyyaml

# Expose port for Flask
EXPOSE 3037

# Default command
CMD ["python3", "app.py"]
