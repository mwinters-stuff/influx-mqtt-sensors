FROM ghcr.io/linuxserver/baseimage-ubuntu:arm64v8-bionic

RUN apt-get update -q -y && apt-get install -q -y wget bash unzip git zip && \
    wget https://storage.googleapis.com/dart-archive/channels/stable/release/2.13.4/sdk/dartsdk-linux-arm64-release.zip && \
    unzip dartsdk-linux-arm64-release.zip && \
    rm dartsdk-linux-arm64-release.zip 
RUN ls && \
    ./dart-sdk/bin/dart pub get && \
    ./dart-sdk/bin/dart compile exe -o influx_mqtt_sensors bin/influx_mqtt_sensors.dart
RUN rm -rf /dart-sdk
