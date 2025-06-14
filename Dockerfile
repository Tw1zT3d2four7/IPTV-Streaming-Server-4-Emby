FROM python:3.11-slim

WORKDIR /app

# Copy all your app files
COPY . .

# Make ffmpeg executable
RUN chmod +x /usr/local/bin/ffmpeg

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Make app.py executable
RUN chmod +x app.py

EXPOSE 3037

CMD ["./app.py"]
