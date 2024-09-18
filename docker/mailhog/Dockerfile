FROM mailhog/mailhog:latest

# Install necessary packages
USER root
RUN apk add --no-cache ca-certificates tzdata

# Copy MailHog binary with file storage support
# Note: Replace the URL with the actual binary that supports file storage
# For demonstration, we'll assume we have a MailHog binary that supports file storage
# You need to build it yourself or find a suitable binary
# Here, we're copying it from the context (make sure to place the binary in docker/mailhog/)
COPY MailHog /usr/local/bin/MailHog

# Set the working directory
WORKDIR /mailhog-data

# Expose ports
EXPOSE 1025 8025

ENTRYPOINT ["/usr/local/bin/MailHog"]
