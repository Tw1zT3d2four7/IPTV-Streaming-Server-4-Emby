# Use NVIDIA base image with CUDA support
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Install system dependencies and hardware acceleration libraries
RUN apt-get update && apt-get install -y \
    git build-essential pkg-config cmake \
    yasm nasm libtool autoconf automake \
    libx264-dev libx265-dev libnuma-dev \
    libfdk-aac-dev libmp3lame-dev libopus-dev \
    libssl-dev libass-dev python3-pip \
    wget curl unzip \
    libva-dev vainfo i965-va-driver libdrm-dev \
    intel-media-va-driver-non-free libmfx-dev \
    mesa-va-drivers \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
COPY requirements.txt /tmp/
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Set working directory for build
WORKDIR /opt

# Build nv-codec-headers (required for CUDA/NVENC)
RUN git clone https://github.com/FFmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make && make install && \
    cd .. && rm -rf nv-codec-headers

# Clone FFmpeg source
RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg

# Build and install FFmpeg with full support
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
    --enable-libass \
    --enable-libmfx \
    --enable-vaapi \
    --enable-protocol=https \
    --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Set working directory for app
WORKDIR /app

# Copy your application code
COPY . .

# Add optional hardware diagnostics script
RUN echo '#!/bin/bash\n' \
         'echo "🛠️ Checking VAAPI support..."\n' \
         'vainfo || echo "VAAPI not supported or unavailable."\n\n' \
         'echo "🛠️ Checking FFmpeg hardware acceleration..."\n' \
         'ffmpeg -hide_banner -hwaccels\n\n' \
         'echo "🚀 Starting server..."\n' \
         'exec "$@"' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

# Run diagnostics then launch app
ENTRYPOINT ["/entrypoint.sh"]
CMD ["gunicorn", "-b", "0.0.0.0:3037", "--timeout", "300", "-k", "gevent", "app:app"]
