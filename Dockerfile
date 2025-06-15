# ---------- Stage 1: Build FFmpeg ----------
FROM ubuntu:22.04 AS ffmpeg-builder

ENV DEBIAN_FRONTEND=noninteractive

# Install core dependencies for building
RUN apt update && apt install -y \
  build-essential git pkg-config cmake meson ninja-build yasm nasm \
  libfdk-aac-dev libvpx-dev libx264-dev libx265-dev libnuma-dev \
  libfreetype-dev libfontconfig1-dev libfribidi-dev libass-dev \
  libvorbis-dev libopus-dev libmp3lame-dev libunistring-dev libaom-dev libopenjp2-7-dev \
  libssl-dev nvidia-cuda-toolkit \
  libdrm-dev libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev \
  libsdl2-dev libxv-dev libva-dev libvdpau-dev zlib1g-dev \
  libpulse-dev python3-pip curl wget unzip \
  && pip install meson ninja

# Build and install libvmaf
RUN git clone https://github.com/Netflix/vmaf.git && \
    cd vmaf/libvmaf && \
    meson setup build --buildtype release && \
    ninja -C build && \
    ninja -C build install && \
    ldconfig

# Build and install nv-codec-headers
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && \
    make -j$(nproc) && make install

# Clone and build FFmpeg
RUN git clone https://github.com/ffmpeg/ffmpeg.git && \
    cd ffmpeg && \
    ./configure --prefix=/usr/local \
      --enable-gpl --enable-nonfree \
      --enable-cuda --enable-cuvid --enable-nvenc --enable-cuda-nvcc \
      --enable-libx264 --enable-libx265 --enable-libvpx --enable-libfdk-aac \
      --enable-libmp3lame --enable-libopus --enable-libass --enable-libvorbis \
      --enable-libfreetype --enable-libfribidi --enable-libfontconfig \
      --enable-libopenjpeg --enable-libvmaf \
      --enable-libdrm --enable-libxcb --enable-libxv \
      --enable-libpulse --enable-libalsa --enable-sdl2 \
      --enable-openssl \
      --enable-libunwind --enable-zlib \
      --disable-debug \
      --extra-cflags="-I/usr/local/include" \
      --extra-ldflags="-L/usr/local/lib" && \
    make -j$(nproc) && \
    make install && \
    ldconfig

# ---------- Stage 2: Final Runtime Image ----------
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt update && apt install -y \
    libnuma1 libva-drm2 libx11-6 libxext6 libxv1 libasound2 libdrm2 \
    libxcb-shape0 libxcb-xfixes0 libsdl2-2.0-0 libpulse0 libvdpau1 \
    libvmaf1 libfdk-aac2 libmp3lame0 libopus0 libass9 libfreetype6 libfontconfig1 \
    libfribidi0 libopenjp2-7 libssl3 libunistring2 libx264-163 libx265-199 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built ffmpeg from builder
COPY --from=ffmpeg-builder /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg-builder /usr/local/lib/ /usr/local/lib/

# Make sure library paths are recognized
ENV LD_LIBRARY_PATH=/usr/local/lib

# Copy your application files
COPY . .

# Make sure your script is executable
RUN chmod +x /usr/local/bin/ffmpeg && chmod +x app.py

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 3037

CMD ["./app.py"]
