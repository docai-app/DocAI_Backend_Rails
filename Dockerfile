FROM ruby:3.1.0

RUN mkdir /usr/local/nvm
ENV NVM_DIR /usr/local/nvm
ENV NODE_VERSION 14.18.1
RUN curl https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install $NODE_VERSION \
    && nvm alias default $NODE_VERSION \
    && nvm use default

ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH

RUN apt-get update -qq && apt-get install -y fonts-wqy-zenhei \
    && apt-get install -y libmagickwand-dev imagemagick \
    && apt-get install -y xvfb libxi6 libgconf-2-4 \
    && apt-get install -qq --no-install-recommends \
    nodejs \
    xfonts-encodings \
    libfontenc1 \
    xfonts-utils \
    xfonts-75dpi \
    xfonts-base \
    fontconfig \
    libjpeg62-turbo \
    libxrender1 \
    libopencc-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g yarn@1

# download and install chrome
RUN curl -sS -o - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
RUN echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list
RUN apt-get update 
#&& apt-get install -y google-chrome-stable

# 設定 CHROMEDRIVER_VERSION 變數
ARG CHROMEDRIVER_VERSION="114.0.5735.90"
ARG CHROME_VERSION="114.0.5735.90-1"

# 使用 ENV 指令將變數設置為環境變數
ENV CHROMEDRIVER_VERSION=$CHROMEDRIVER_VERSION
ENV CHROME_VERSION=${CHROME_VERSION}

# download chrome
RUN wget --no-verbose -O /tmp/chrome.deb https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_114.0.5735.90-1_amd64.deb \
    && apt install -y /tmp/chrome.deb \
    && rm /tmp/chrome.deb

# download and install chromedriver
RUN CHROMEDRIVER_VERSION=`curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE` && \
    curl -sS -o /tmp/chromedriver_linux64.zip http://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VERSION/chromedriver_linux64.zip && \
    unzip /tmp/chromedriver_linux64.zip -d /usr/local/bin && \
    rm /tmp/chromedriver_linux64.zip && \
    chmod +x /usr/local/bin/chromedriver

ENV DISPLAY=:99

# install wkhtmltopdf
# RUN apt-get install -y fontconfig libjpeg62-turbo libxrender1
# RUN apt-get install -y xfonts-encodings libfontenc1 xfonts-utils xfonts-75dpi xfonts-base
RUN wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.bullseye_amd64.deb 
RUN dpkg -i wkhtmltox_0.12.6.1-2.bullseye_amd64.deb

# install fonts
RUN wget https://fonts.google.com/download?family=Noto%20Sans%20SC -O NotoSC.zip
RUN wget https://fonts.google.com/download?family=Noto%20Sans%20TC -O NotoTC.zip
RUN unzip -o NotoSC.zip
RUN unzip -o NotoTC.zip
# RUN cp *.otf /usr/share/fonts/

WORKDIR /docai-rails
COPY Gemfile /docai-rails/Gemfile
COPY Gemfile.lock /docai-rails/Gemfile.lock
RUN bundle install
COPY . /docai-rails

CMD ["sh", "-c", "Xvfb :99 -screen 0 1920x1080x24 -ac +extension RANDR &"]

# RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rake assets:precompile
#CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
