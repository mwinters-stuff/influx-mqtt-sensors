FROM ghcr.io/linuxserver/baseimage-ubuntu:amd64-bionic

RUN apt-get update -q -y && apt-get install -q -y wget bash unzip git zip && \
    echo "getting dart sdk" && \
    # wget -q https://storage.googleapis.com/dart-archive/channels/stable/release/2.13.4/sdk/dartsdk-linux-arm64-release.zip && \
    wget -q https://storage.googleapis.com/dart-archive/channels/stable/release/2.15.1/sdk/dartsdk-linux-x64-release.zip && \
    echo "unzipping dart sdk" && \
    unzip -q dartsdk-linux-*-release.zip && \
    rm dartsdk-linux-*-release.zip 
COPY . /src
WORKDIR /src
RUN ls && \
    /dart-sdk/bin/dart pub get && \
    /dart-sdk/bin/dart compile exe -o /usr/local/bin/influx_mqtt_sensors bin/influx_mqtt_sensors.dart
RUN rm -rf /dart-sdk
COPY dockerfiles/root/ /



