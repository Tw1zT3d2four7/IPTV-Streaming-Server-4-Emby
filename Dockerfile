# Use full Python image (not slim!)
FROM python:3.11

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Copy ffmpeg into the container's system path
COPY custom-ffmpeg/ffmpeg /usr/local/bin/ffmpeg

# Make sure it's executable
RUN chmod +x /usr/local/bin/ffmpeg

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Make app.py executable
RUN chmod +x app.py

# Expose the port
EXPOSE 3037

# Run the app
CMD ["./app.py"]

