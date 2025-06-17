# Use NVIDIA base image with CUDA support
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04

# Install base build tools and dependencies, including python3-venv
RUN apt-get update && apt-get install -y \
    git build-essential pkg-config cmake \
    yasm nasm libtool autoconf automake \
    libx264-dev libx265-dev libnuma-dev \
    libfdk-aac-dev libmp3lame-dev libopus-dev \
    libssl-dev libass-dev \
    python3-pip python3-venv \
    wget curl unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Python packages (initially via system pip3)
COPY requirements.txt /tmp/
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Set working directory
WORKDIR /opt

# Clone nv-codec-headers (required for FFmpeg CUDA support)
RUN git clone https://github.com/FFmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make && make install && \
    cd .. && rm -rf nv-codec-headers

# Clone FFmpeg source
RUN git clone https://github.com/FFmpeg/FFmpeg.git ffmpeg

# Build FFmpeg with necessary options
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
    --enable-shared && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# Set working directory for your app
WORKDIR /app

# Copy your app source code
COPY . .

# Create Python virtual environment and install dependencies
RUN python3 -m venv /venv
RUN /venv/bin/pip install --upgrade pip
RUN /venv/bin/pip install -r requirements.txt

# Set the virtual environment path
ENV PATH="/venv/bin:$PATH"

# Run the app with Gunicorn
CMD ["gunicorn", "-b", "0.0.0.0:3037", "--timeout", "300", "-k", "gevent", "app:app"]
