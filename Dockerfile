# ---------- Stage 1: Build FFmpeg ----------
FROM ubuntu:24.04 AS ffmpeg-builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential git pkg-config cmake meson ninja-build yasm nasm \
  libfdk-aac-dev libvpx-dev libx264-dev libx265-dev libnuma-dev \
  libfreetype6-dev libfontconfig1-dev libfribidi-dev libass-dev \
  libvorbis-dev libopus-dev libmp3lame-dev libunistring-dev libaom-dev libopenjp2-7-dev \
  libssl-dev libdrm-dev libxcb1-dev libxcb-shape0-dev libxcb-xfixes0-dev libxcb-shm0-dev \
  libasound2-dev libsdl2-dev libxv-dev libva-dev libvdpau-dev zlib1g-dev \
  libpulse-dev libunwind-dev wget curl unzip autoconf automake libtool python3-pip \
  nvidia-cuda-toolkit \
  && pip3 install meson \
  && rm -rf /var/lib/apt/lists/*

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

# Build FFmpeg with all required libs and CUDA
RUN git clone https://github.com/ffmpeg/ffmpeg.git && \
    cd ffmpeg && \
    ./configure --prefix=/ffmpeg-build \
      --enable-gpl --enable-nonfree \
      --enable-cuda --enable-cuvid --enable-nvenc --enable-cuda-nvcc \
      --enable-libx264 --enable-libx265 --enable-libvpx --enable-libfdk-aac \
      --enable-libmp3lame --enable-libopus --enable-libass --enable-libvorbis \
      --enable-libfreetype --enable-libfribidi --enable-libfontconfig \
      --enable-libopenjpeg --enable-libvmaf \
      --enable-libdrm --enable-libxcb --enable-libxv \
      --enable-libpulse --enable-libalsa --enable-sdl2 \
      --enable-openssl --enable-libunwind --enable-zlib \
      --extra-cflags="-I/usr/local/include" \
      --extra-ldflags="-L/usr/local/lib" \
      --disable-debug && \
    make -j$(nproc) && make install && ldconfig

# ---------- Stage 2: Runtime Image ----------
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies for FFmpeg and your app
RUN apt-get update && apt-get install -y --no-install-recommends \
  libnuma1 libva-drm2 libx11-6 libxext6 libxv1 libasound2 libdrm2 \
  libxcb-shape0 libxcb-xfixes0 libxcb-shm0 libsdl2-2.0-0 libpulse0 libvdpau1 \
  libfdk-aac2 libmp3lame0 libopus0 libass9 libfreetype6 libfontconfig1 \
  libfribidi0 libopenjp2-7 libssl-dev libunistring2 zlib1g python3 python3-pip \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy ffmpeg from build stage
COPY --from=ffmpeg-builder /ffmpeg-build/bin/ffmpeg /usr/local/bin/ffmpeg

# Copy your app files (adjust paths as needed)
COPY . .

# Make sure ffmpeg and app script are executable
RUN chmod +x /usr/local/bin/ffmpeg && chmod +x app.py

# Install python dependencies
RUN pip3 install --no-cache-dir -r requirements.txt

# Expose your app port
EXPOSE 3037

# Run your app
CMD ["./app.py"]
