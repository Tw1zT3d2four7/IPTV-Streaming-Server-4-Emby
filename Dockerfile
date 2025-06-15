# Use Python base image
FROM python:3.11-slim

# Install shared libs needed by custom ffmpeg
RUN apt-get update && apt-get install -y \
    libdrm2 \
    libx11-6 \
    libxext6 \
    libva2 \
    libvdpau1 \
    libgl1 \
    libglx0 \
    libxcb1 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Make app.py executable
RUN chmod +x app.py

# Expose the port
EXPOSE 3037

# Run the app
CMD ["./app.py"]
