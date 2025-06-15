FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    ffmpeg \
    python3 \
    python3-pip \
    python3-yaml \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy app files
COPY . /app

# Install Python dependencies
RUN pip3 install flask pyyaml

# Expose port
EXPOSE 3037

# Run app
CMD ["python3", "app.py"]
