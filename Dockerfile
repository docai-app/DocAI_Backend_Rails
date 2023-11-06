FROM ruby:3.1.0

# RUN curl -sL https://deb.nodesource.com/setup_18.x | bash -
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash
RUN . ~/.nvm/nvm.sh && nvm install node
# RUN apt-get update -qq && apt-get install -qq --no-install-recommends \
#     nodejs \
#     && apt-get clean \
#     && rm -rf /var/lib/apt/lists/* \
#     && apt-get install -y xfonts-encodings libfontenc1 xfonts-utils xfonts-75dpi xfonts-base
RUN apt-get install -y fonts-wqy-zenhei \
    && apt-get install -y libmagickwand-dev imagemagick \
    && apt-get update -qq \
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g yarn@1

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

# RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rake assets:precompile
#CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

