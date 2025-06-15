# ---------- Stage 1: Build FFmpeg ----------
FROM ubuntu:22.04 AS ffmpeg-builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools and dev libs
RUN apt update && apt install -y \
  build-essential git pkg-config cmake meson ninja-build yasm nasm \
  libfdk-aac-dev libvpx-dev libx264-dev libx265-dev libnuma-dev \
  libfreetype-dev libfontconfig1-dev libfribidi-dev libass-dev \
  libvorbis-dev libopus-dev libmp3lame-dev libunistring-dev libaom-dev libopenjp2-7-dev \
  libssl-dev \
  nvidia-cuda-toolkit \
  libdrm-dev libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev \
  libxv-dev wget curl unzip autoconf automake libtool python3-pip && \
  pip install meson

# Build libvmaf
RUN git clone https://github.com/Netflix/vmaf.git && \
    cd vmaf/libvmaf && \
    meson setup build --buildtype release && \
    ninja -C build && \
    ninja -C build install && \
    ldconfig

# Build nv-codec-headers
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make -j$(nproc) && make install

# Build FFmpeg
RUN git clone https://github.com/ffmpeg/ffmpeg.git && \
    cd ffmpeg && \
    ./configure --prefix=/ffmpeg-build \
        --enable-gpl --enable-nonfree \
        --enable-cuda --enable-cuvid --enable-nvenc --enable-cuda-nvcc \
        --enable-libx264 --enable-libx265 --enable-libvpx --enable-libfdk-aac \
        --enable-libmp3lame --enable-libopus --enable-libass --enable-libvorbis \
        --enable-libfreetype --enable-libfribidi --enable-libfontconfig \
        --enable-libopenjpeg --enable-libvmaf \
        --enable-openssl \
        --extra-cflags=-I/usr/local/include --extra-ldflags=-L/usr/local/lib \
        --disable-debug && \
    make -j$(nproc) && make install

# ---------- Stage 2: Final Image ----------
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install only runtime dependencies (including missing xcb libs)
RUN apt update && apt install -y \
    libnuma1 libva-drm2 libx11-6 libxext6 libxv1 libasound2 libdrm2 \
    libxcb-shape0 libxcb-xfixes0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built ffmpeg binary
COPY --from=ffmpeg-builder /ffmpeg-build/bin/ffmpeg /usr/local/bin/ffmpeg

# Copy your project files
COPY . .

# Ensure executables have correct permissions
RUN chmod +x /usr/local/bin/ffmpeg && chmod +x app.py

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose your app's port
EXPOSE 3037

# Run your app
CMD ["./app.py"]
