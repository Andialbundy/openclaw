#!/bin/sh

# Fix permissions on mounted volumes and app directory
chown -R openclaw:openclaw /app
if [ -d /home/node/.openclaw ]; then
  chown -R openclaw:openclaw /home/node/.openclaw
fi

# Execute CMD arguments passed from docker run/compose
exec "$@"
