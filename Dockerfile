# Use NVIDIA CUDA base image
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Install base tools and all dependencies including VAAPI libs and drivers
RUN apt-get update && apt-get install -y \
    git build-essential pkg-config cmake \
    yasm nasm libtool autoconf automake \
    libx264-dev libx265-dev libnuma-dev \
    libfdk-aac-dev libmp3lame-dev libopus-dev \
    libssl-dev libass-dev python3-pip \
    wget curl unzip \
    libva-dev vainfo i965-va-driver libdrm-dev \
    libmfx1 intel-media-va-driver-non-free \
    vainfo mesa-va-drivers \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (gunicorn included in requirements)
COPY requirements.txt /tmp/
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Set working directory for building nv-codec-headers
WORKDIR /opt

# Clone and install nv-codec-headers for NVIDIA hw accel
RUN git clone https://github.com/FFmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make && make install && \
    cd .. && rm -rf nv-codec-headers

# Clone FFmpeg source
RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg

WORKDIR /opt/ffmpeg

# Configure FFmpeg with all needed options including hardware acceleration
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
    --enable-libass \
    --enable-protocol=https \
    --enable-libmfx \
    --enable-vaapi \
    --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Set workdir for your app
WORKDIR /app

# Copy app files (adjust as needed)
COPY . .

# Expose port and run with Gunicorn and Gevent worker (adjust if needed)
CMD ["gunicorn", "-b", "0.0.0.0:3037", "--timeout", "300", "-k", "gevent", "app:app"]
