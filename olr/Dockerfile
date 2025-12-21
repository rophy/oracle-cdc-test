FROM rophy/openlogreplicator:v1.8.7-5-g0cdc866

USER root

RUN groupadd -g 54321 oinstall && \
    usermod -aG oinstall user1

USER user1
