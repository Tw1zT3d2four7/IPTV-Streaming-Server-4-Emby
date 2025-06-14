# Use Python base image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Install Python dependencies if you have any
 RUN pip install -r requirements.txt

# Make app.py executable
RUN chmod +x app.py

# Expose the port your app runs on
EXPOSE 3037

# Run app.py directly
CMD ["./app.py"]
