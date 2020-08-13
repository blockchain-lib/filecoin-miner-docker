# build container stage
FROM golang:1.14 AS build-env
ENV RUSTFLAGS="-C target-cpu=native -g"
ENV FFI_BUILD_FROM_SOURCE=1
RUN apt-get update -y && \
    apt-get install sudo curl git mesa-opencl-icd ocl-icd-opencl-dev gcc git bzr jq pkg-config -y
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o rustup-init.sh && \
    chmod +x rustup-init.sh && \
    ./rustup-init.sh -y 
ENV PATH="$PATH:/root/.cargo/bin"
RUN git clone https://github.com/filecoin-project/lotus.git && \
    cd lotus && \
    git pull && \
    git fetch --tags && \
    latestTag=$(git describe --tags `git rev-list --tags --max-count=1`) && \
    #git checkout $latestTag && \
    #git checkout interopnet && \
    git checkout master && \
    /bin/bash -c "source /root/.cargo/env" && \
    make clean && \
    make build && \
    make bench && \
    make lotus chainwatch && \
    install -C ./lotus /usr/local/bin/lotus && \
    install -C ./lotus-storage-miner /usr/local/bin/lotus-storage-miner && \
    install -C ./lotus-seal-worker /usr/local/bin/lotus-seal-worker && \
    install -C ./chainwatch /usr/local/bin/chainwatch && \
    install -C ./bench /usr/local/bin/bench

# runtime container stage
FROM nvidia/cuda:10.1-base-ubuntu18.04 
ENV DEBIAN_FRONTEND=noninteractive
RUN apt update && \
    apt upgrade -y && \
    apt install nvidia-driver-440 mesa-opencl-icd ocl-icd-opencl-dev -y
COPY --from=build-env /usr/local/bin/lotus /usr/local/bin/lotus
COPY --from=build-env /usr/local/bin/lotus-storage-miner /usr/local/bin/lotus-storage-miner
COPY --from=build-env /usr/local/bin/lotus-seal-worker /usr/local/bin/lotus-seal-worker
COPY --from=build-env /usr/local/bin/chainwatch /usr/local/bin/chainwatch
COPY --from=build-env /usr/local/bin/bench /usr/local/bin/bench
COPY --from=build-env /etc/ssl/certs /etc/ssl/certs
COPY LOTUS_VERSION /VERSION

COPY --from=build-env /lib/x86_64-linux-gnu/libdl.so.2 /lib/libdl.so.2
COPY --from=build-env /lib/x86_64-linux-gnu/libutil.so.1 /lib/libutil.so.1 
COPY --from=build-env /usr/lib/x86_64-linux-gnu/libOpenCL.so.1.0.0 /lib/libOpenCL.so.1
COPY --from=build-env /lib/x86_64-linux-gnu/librt.so.1 /lib/librt.so.1
COPY --from=build-env /lib/x86_64-linux-gnu/libgcc_s.so.1 /lib/libgcc_s.so.1

COPY config/config.toml /root/config.toml
COPY scripts/entrypoint /bin/entrypoint

# API port
EXPOSE 1234/tcp

# P2P port
EXPOSE 1235/tcp

ENTRYPOINT ["/usr/local/bin/bench"]
