#!/bin/sh

# Fix permissions on mounted volumes and app directory (async, don't block startup)
( chown -R openclaw:openclaw /app 2>/dev/null
  [ -d /home/node/.openclaw ] && chown -R openclaw:openclaw /home/node/.openclaw 2>/dev/null
) &

# Execute CMD arguments passed from docker run/compose
exec "$@"
