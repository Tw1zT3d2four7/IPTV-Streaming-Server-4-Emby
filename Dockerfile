# Use Python base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Copy custom ffmpeg from host into container
# NOTE: This assumes you're building the image on the same host that has ffmpeg
COPY /usr/local/bin/ffmpeg /usr/local/bin/ffmpeg

# Make sure ffmpeg is executable
RUN chmod +x /usr/local/bin/ffmpeg

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Make app.py executable
RUN chmod +x app.py

# Expose the port your app runs on
EXPOSE 3037

# Run app.py directly
CMD ["./app.py"]

