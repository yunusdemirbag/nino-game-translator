# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Nino contributors
#
# Nino Linux sunucusunun imajı. Depo kökünden derlenir:  ./apps/linux/build.sh
# Aşamalar: LG/Samsung TV paketleri → yerel PS5 kütüphanesi (nino_native.so) → .NET yayını → çalışma imajı.
# Hepsi Ubuntu 24.04 tabanlı; yerel kütüphane FFmpeg'i statik içerir. Android TV paketi (.apk)
# isteğe bağlıdır: varsa apps/linux/tv-apk/ altına konur. Sunucu paketleri TV'ye kendisi kurar.
# Ortak çekirdek ve nino_native kaynağı apps/windows altındadır. chiaki-ng kaynağını build.sh indirir.

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS tv
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3 >/dev/null
WORKDIR /src
COPY apps/tv-web apps/tv-web
RUN python3 apps/tv-web/tools/package.py && mkdir -p /tv-app && cp apps/tv-web/dist/*.ipk apps/tv-web/dist/*.wgt /tv-app/

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS native
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      build-essential cmake ninja-build pkg-config nasm python3 python3-protobuf protobuf-compiler \
      libssl-dev libjson-c-dev libevent-dev libminiupnpc-dev curl xz-utils >/dev/null
WORKDIR /src
COPY core/NinoRemotePlay/Vendor/chiaki-ng third-party/chiaki-ng
COPY apps/windows/native apps/windows/native
# FFmpeg betikte en küçük hâliyle statik derlenir; .so dağıtımın FFmpeg'ine bağlanmaz.
RUN NINO_CHIAKI_DIR=/src/third-party/chiaki-ng apps/windows/native/scripts/build-linux.sh \
 && mkdir -p /build && cp apps/windows/native/bin/nino_native.so /build/ && strip /build/nino_native.so

FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS app
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
WORKDIR /src
COPY --from=tv /tv-app dist/tv-app
COPY apps/linux/tv-ap[k] dist/tv-app/
COPY apps/windows/Directory.Build.props apps/windows/Directory.Build.props
COPY apps/windows/src apps/windows/src
COPY apps/linux apps/linux
RUN dotnet publish apps/linux/src/Nino.Linux -c Release -o /app --nologo -v q
COPY --from=native /build/nino_native.so /app/nino_native.so

# Sınama aşaması (imaja girmez): docker build --target test ...
FROM app AS test
RUN dotnet test apps/linux/Nino.Linux.slnx -c Release --nologo -v q

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble
# libchiaki'nin çalışma kütüphaneleri, ONNX çalışma zamanının OpenMP'si, Tesseract (yazı tanıma), ssh-keygen (LG geliştirici anahtarı).
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      libjson-c5 libminiupnpc17 libevent-2.1-7t64 libevent-pthreads-2.1-7t64 \
      libssl3t64 zlib1g libgomp1 python3 python3-venv libtesseract5 tesseract-ocr-eng openssh-client ca-certificates >/dev/null \
 && rm -rf /var/lib/apt/lists/*
COPY --from=app /app /app
# Ücretsiz Türkçe model (CTranslate2) Python işçisiyle çalışır: ctranslate2 (MIT) ayrı bir sanal ortama kurulur ve
# çekirdeğin beklediği yere (/app/ct2/python3, yanında worker.py) küçük bir başlatıcıyla bağlanır. Sembolik bağlantı
# olmaz: Python sanal ortamını çağrıldığı yolun yanında arar. Sürüm Windows'un çalışma zamanıyla aynı.
# Eski ONNX modeli olan kurulumlar buna gerek duymaz.
RUN python3 -m venv /opt/ct2 && /opt/ct2/bin/pip install --no-cache-dir -q ctranslate2==4.9.0 \
 && printf '#!/bin/sh\nexec /opt/ct2/bin/python3 "$@"\n' > /app/ct2/python3 && chmod +x /app/ct2/python3 \
 && /app/ct2/python3 -c "import ctranslate2" && test -f /app/ct2/worker.py
# Eksik paylaşımlı kütüphane derlemede yakalansın, çalışırken değil.
RUN if ldd /app/nino_native.so | grep "not found"; then exit 1; fi \
 && mkdir -p /data && chown "$APP_UID" /data
# OMP_THREAD_LIMIT=1: Tesseract'ın OpenMP iş parçacıkları kısa satırda hız kazandırmaz, işlemciyi doldurur.
ENV NINO_DATA=/data HOME=/data OMP_THREAD_LIMIT=1
VOLUME /data
USER $APP_UID
WORKDIR /app
# 8788 panel, 8787 eski TV uygulamaları, 47800 yeni protokol. PS5 ve TV'yi bulmak için ev ağına doğrudan
# bağlı çalışmalı (compose.yml: network_mode: host).
EXPOSE 8788 8787 47800
ENTRYPOINT ["dotnet", "/app/nino.dll"]
