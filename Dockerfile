# Use full Python image (not slim!)
FROM python:3.11

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Copy your custom FFmpeg binary
COPY ffmpeg /home/jeremy/Media_Server/IPTV-Streaming-Server-4-Emby-main/custom-ffmpeg

# Make sure it's executable
RUN chmod +x /home/jeremy/Media_Server/IPTV-Streaming-Server-4-Emby-main/custom-ffmpeg

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Make app.py executable
RUN chmod +x app.py

# Expose the port
EXPOSE 3037

# Run the app
CMD ["./app.py"]

