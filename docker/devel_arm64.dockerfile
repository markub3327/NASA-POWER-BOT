# nainstaluj Ubuntu 20.04 LTS
FROM ubuntu:20.04

# nastav jazyk
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

ARG DEBIAN_FRONTEND=noninteractive

###########################################
# Dependencies
###########################################
RUN apt update && apt install -y \
    curl \
    openssh-server \
    build-essential \
    git \
    tar \
    htop \
    && rm -rf /var/lib/apt/lists/*

###########################################
# Install Julia
###########################################
RUN curl https://julialang-s3.julialang.org/bin/linux/aarch64/1.7/julia-1.7.3-linux-aarch64.tar.gz -o julia-1.7.3-linux-aarch64.tar.gz
RUN tar -xvzf julia-1.7.3-linux-aarch64.tar.gz
RUN mv julia-1.7.3/ /opt/julia
RUN ln -s /opt/julia/bin/julia /usr/local/bin/julia

###########################################
# Setting up SSH
###########################################
EXPOSE 2222

ENV SSH_PASSWD "root:Docker!"
RUN echo "$SSH_PASSWD" | chpasswd 
COPY docker/config/sshd_config /etc/ssh/

###########################################
# Create working directory
###########################################
RUN mkdir /root/code

COPY docker/config/init.sh /usr/local/bin/
ENTRYPOINT [ "sh", "/usr/local/bin/init.sh" ]