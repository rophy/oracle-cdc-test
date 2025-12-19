FROM rophy/openlogreplicator:1.8.7

USER root

# Change user1 from 1000:1000 to 54321:54321 to match Oracle's oracle:oinstall
RUN groupmod -g 54321 user1 && \
    usermod -u 54321 -g 54321 user1 && \
    # Fix ownership of any files owned by old UID/GID
    find / -xdev -user 1000 -exec chown 54321 {} \; 2>/dev/null || true && \
    find / -xdev -group 1000 -exec chgrp 54321 {} \; 2>/dev/null || true

USER user1
