# Use NVIDIA base image with CUDA support
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Install base build tools and dependencies + VAAPI + QSV libs
RUN apt-get update && apt-get install -y \
    git build-essential pkg-config cmake \
    yasm nasm libtool autoconf automake \
    libx264-dev libx265-dev libnuma-dev \
    libfdk-aac-dev libmp3lame-dev libopus-dev \
    libssl-dev libass-dev python3-pip \
    wget curl unzip \
    libmfx-dev \
    intel-media-va-driver-non-free \
    vainfo \
    vainfo \
    i965-va-driver-shaders \
    vainfo \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages (includes Gunicorn via requirements.txt)
COPY requirements.txt /tmp/
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Set working directory
WORKDIR /opt

# Clone and build NVIDIA codec headers (needed for NVENC, CUVID, etc.)
RUN git clone https://github.com/FFmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make && make install && \
    cd .. && rm -rf nv-codec-headers

# Clone and build FFmpeg
RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg

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
    --enable-protocol=https \
    --enable-libmfx \
    --enable-vaapi \
    --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Set application directory
WORKDIR /app

# Copy application code
COPY . .

# Run with Gunicorn in production mode using gevent worker class
CMD ["gunicorn", "-b", "0.0.0.0:3037", "--timeout", "300", "-k", "gevent", "app:app"]
