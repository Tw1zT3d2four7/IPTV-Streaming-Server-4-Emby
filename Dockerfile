# Use an NVIDIA CUDA base image
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Avoid interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install OS packages
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    wget \
    ca-certificates \
    yasm \
    nasm \
    libx264-dev \
    libx265-dev \
    libfdk-aac-dev \
    libmp3lame-dev \
    libopus-dev \
    libass-dev \
    libssl-dev \
    pkg-config \
    python3 \
    python3-pip \
    python3-setuptools \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt /app/requirements.txt
RUN pip3 install --no-cache-dir -r /app/requirements.txt

# Optional: Build FFmpeg with NVIDIA support
WORKDIR /opt
RUN git clone https://git.ffmpeg.org/ffmpeg.git ffmpeg
WORKDIR /opt/ffmpeg

# Clone and install ffnvcodec headers (needed for --enable-cuda)
RUN git clone https://git.videolan.org/git/ffnvcodec.git && \
    cd ffnvcodec && \
    make install && \
    cd ..

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
    --enable-libass \
    --enable-openssl \
    --enable-protocol=https \
    --enable-shared \
    && make -j$(nproc) \
    && make install \
    && ldconfig

# Copy your app
WORKDIR /app
COPY . /app

# Run your Flask app
CMD ["python3", "app.py"]
