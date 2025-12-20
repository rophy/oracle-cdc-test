FROM tpcorg/hammerdb:v4.10

USER root

# Create user with UID/GID 1000 to match local user for volume permissions
RUN groupadd -g 1000 hammerdb && \
    useradd -u 1000 -g 1000 -m hammerdb && \
    chown -R 1000:1000 /home/HammerDB-4.10

USER hammerdb
