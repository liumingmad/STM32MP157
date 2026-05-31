FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bc \
        bison \
        build-essential \
        ca-certificates \
        curl \
        file \
        flex \
        gcc-arm-linux-gnueabihf \
        kmod \
        libelf-dev \
        libssl-dev \
        make \
        pkg-config \
        rsync \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work
