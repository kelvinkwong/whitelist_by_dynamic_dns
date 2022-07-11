FROM ubuntu:latest

ENV TZ=Australia/Sydney

RUN apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y  dnsutils \
                        iproute2 \
                        ufw \
                        vim && \
    apt-get clean -y

# RUN After adding capabilities
# RUN ufw enable

WORKDIR /root
