# Base: NVIDIA CUDA runtime on Ubuntu 22.04
FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip git make build-essential pkg-config yasm \
    libx264-dev libx265-dev libnuma-dev libfdk-aac-dev \
    libmp3lame-dev libopus-dev libass-dev libssl-dev \
    curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Set Python 3 as default
RUN ln -s /usr/bin/python3 /usr/bin/python && ln -s /usr/bin/pip3 /usr/bin/pip

# Install Python dependencies
RUN pip install --upgrade pip && \
    pip install Flask==2.3.2 PyYAML==6.0 gunicorn

# Set working directory
WORKDIR /opt

# Clone FFmpeg and required headers for NVIDIA encoding
RUN git clone https://github.com/FFmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make && make install && \
    cd .. && rm -rf nv-codec-headers

RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg && \
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
        --enable-libopus \
        --enable-libass \
        --enable-openssl \
        --enable-shared \
        --enable-pic \
        --enable-protocol=https && \
    make -j$(nproc) && \
    make install && \
    ldconfig && \
    cd .. && rm -rf ffmpeg

# Move to app directory
WORKDIR /app

# Copy application code
COPY . .

# Expose the Flask/Gunicorn port
EXPOSE 3037

# Run Gunicorn WSGI server
CMD ["gunicorn", "-b", "0.0.0.0:3037", "app:app"]
