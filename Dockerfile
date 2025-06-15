# ---------- Stage 1: Build FFmpeg ----------
FROM ubuntu:22.04 AS ffmpeg-builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build tools and dependencies
RUN apt update && apt install -y \
  build-essential git pkg-config cmake meson ninja-build yasm nasm \
  libfdk-aac-dev libvpx-dev libx264-dev libx265-dev libnuma-dev \
  libfreetype-dev libfontconfig1-dev libfribidi-dev libass-dev \
  libvorbis-dev libopus-dev libmp3lame-dev libunistring-dev libaom-dev libopenjp2-7-dev \
  libssl-dev nvidia-cuda-toolkit \
  libdrm-dev libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev \
  libsdl2-dev libxv-dev libva-dev libvdpau-dev zlib1g-dev \
  libpulse-dev libunwind-dev wget curl unzip autoconf automake libtool python3-pip && \
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

# Clone and build FFmpeg
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
      --disable-debug \
      --extra-cflags="-I/usr/local/include" \
      --extra-ldflags="-L/usr/local/lib" && \
    make -j$(nproc) && make install && \
    ldconfig

# ---------- Stage 2: Runtime Container ----------
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV LD_LIBRARY_PATH=/usr/local/lib

# Install runtime dependencies only
RUN apt update && apt install -y \
  libnuma1 libva-drm2 libx11-6 libxext6 libxv1 libasound2 libdrm2 \
  libxcb-shape0 libxcb-xfixes0 libsdl2-2.0-0 libpulse0 libvdpau1 \
  libfdk-aac2 libmp3lame0 libopus0 libass9 libfreetype6 libfontconfig1 \
  libfribidi0 libopenjp2-7 libssl3 libunistring2 zlib1g \
  && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy FFmpeg binary and libs
COPY --from=ffmpeg-builder /ffmpeg-build/bin/ffmpeg /usr/local/bin/ffmpeg
COPY --from=ffmpeg-builder /usr/local/lib/ /usr/local/lib/

# Copy your project files
COPY . .

# Make executables runnable
RUN chmod +x /usr/local/bin/ffmpeg && chmod +x app.py

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Expose app port
EXPOSE 3037

# Start your application
CMD ["./app.py"]
