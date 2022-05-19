FROM ryanpratt/ffmpeg:enable-srt

# We require a local certificate file so set that up.
# You must place a valid cert.pem file in your COSMOS development folder for this work
# Comment out these lines if this is not required in your environment
COPY --from=ballaerospace/cosmosc2-base /devel/cacert.pem /devel/cacert.pem
ENV SSL_CERT_FILE=/devel/cacert.pem
ENV CURL_CA_BUNDLE=/devel/cacert.pem
ENV REQUESTS_CA_BUNDLE=/devel/cacert.pem
ENV NOKOGIRI_USE_SYSTEM_LIBRARIES=1

COPY --from=ballaerospace/cosmosc2-base /root/.gemrc /root/.gemrc

COPY --from=ballaerospace/cosmosc2-base /cosmos/ /cosmos/
ENV COSMOS_PATH="/cosmos"
ENV RUBYLIB=/cosmos/lib:/enterprise-cosmos/lib

WORKDIR /cosmos/plugins/hls-stream/

COPY Gemfile .

RUN apk update \
  && apk add --update ruby \
  ruby-etc \
  ruby-bigdecimal \
  ruby-io-console \
  ruby-irb \
  ca-certificates \
  libressl \
  less \
  tini \
  git \
  libxml2-dev \
  libxslt-dev \
  && apk add --virtual .build-dependencies \
  build-base \
  libressl-dev \
  ruby-dev \
  libressl-dev \
  && git config --global http.sslCAinfo /devel/cacert.pem \
  && gem update --system \
  && gem install bundler || apk add ruby-bundler \
  && gem install rake || apk add ruby-rake \
  && bundle config set --local without 'development' \
  && bundle config build.nokogiri --use-system-libraries \
  && bundle install --quiet \
  && gem cleanup \
  && apk del .build-dependencies \
  && rm -rf /usr/lib/ruby/gems/*/cache/* \
  /var/cache/apk/* \
  /tmp/* \
  /var/tmp/*

COPY ./ /cosmos/plugins/hls-stream/

CMD [ "rackup", "-o", "0.0.0.0", "-p", "11935" ]