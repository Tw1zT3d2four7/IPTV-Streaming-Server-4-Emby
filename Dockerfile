# ---------- Stage 1: Build FFmpeg ----------
FROM ubuntu:24.04 AS ffmpeg-builder

ENV DEBIAN_FRONTEND=noninteractive

# Update and upgrade system first
RUN apt-get update && apt-get upgrade -y

# Install base build tools
RUN apt-get install -y --fix-missing \
  build-essential git pkg-config cmake meson ninja-build yasm nasm

# Install codec dev libraries part 1
RUN apt-get install -y --fix-missing \
  libfdk-aac-dev libvpx-dev libx264-dev libx265-dev libnuma-dev

# Codec dev libraries part 2
RUN apt-get install -y --fix-missing \
  libfreetype6-dev libfontconfig1-dev libfribidi-dev libass-dev

# More codec and utility libs
RUN apt-get install -y --fix-missing \
  libvorbis-dev libopus-dev libmp3lame-dev libunistring-dev libaom-dev libopenjp2-7-dev

# SSL, DRM, XCB related libs
RUN apt-get install -y --fix-missing \
  libssl-dev libdrm-dev libxcb1-dev libxcb-shape0-dev libxcb-xfixes0-dev libxcb-shm0-dev

# Audio, video, and compression libs
RUN apt-get install -y --fix-missing \
  libasound2-dev libsdl2-dev libxv-dev libva-dev libvdpau-dev zlib1g-dev

# Other dependencies + CUDA toolkit + python pip
RUN apt-get install -y --fix-missing \
  libpulse-dev libunwind-dev wget curl unzip autoconf automake libtool python3-pip nvidia-cuda-toolkit

# Install meson with pip
RUN pip install meson

# Build libvmaf
RUN git clone https://github.com/Netflix/vmaf.git && \
    cd vmaf/libvmaf && \
    meson setup build --buildtype release && \
    ninja -C build && ninja -C build install && ldconfig

# Build nv-codec-headers
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git && \
    cd nv-codec-headers && make -j$(nproc) && make install

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
      --enable-libdrm --enable-libxcb --enable-libxv \
      --enable-libpulse --enable-libalsa --enable-sdl2 \
      --enable-openssl --enable-libunwind --enable-zlib \
      --extra-cflags="-I/usr/local/include" \
      --extra-ldflags="-L/usr/local/lib" \
      --disable-debug && \
    make -j$(nproc) && make install && ldconfig

# ---------- Stage 2: Final Runtime Image ----------
FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive

# Runtime libs required by ffmpeg + your app
RUN apt-get update && apt-get install -y --fix-missing \
  libnuma1 libva-drm2 libx11-6 libxext6 libxv1 libasound2 libdrm2 \
  libxcb-shape0 libxcb-xfixes0 libxcb-shm0 libsdl2-2.0-0 libpulse0 libvdpau1 \
  libfdk-aac2 libmp3lame0 libopus0 libass9 libfreetype6 libfontconfig1 \
  libfribidi0 libopenjp2-7 libssl3 libunistring2 zlib1g \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy ffmpeg binary from build stage
COPY --from=ffmpeg-builder /ffmpeg-build/bin/ffmpeg /usr/local/bin/ffmpeg

# Copy your app files (adjust as necessary)
COPY . .

# Fix permissions
RUN chmod +x /usr/local/bin/ffmpeg && chmod +x app.py

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

EXPOSE 3037

CMD ["./app.py"]
