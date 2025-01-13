FROM ubuntu:22.04

# Set working directory
WORKDIR /app

# Install required packages: curl and jq
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy the shell script into the image and make it executable.
COPY ./scripts/ /app/scripts/
RUN chmod -R +x /app/scripts/

# Set the default command to run the script
ENTRYPOINT ["/bin/bash", "/app/scripts/garmin-daily.sh"]
