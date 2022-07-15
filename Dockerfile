FROM ruby:3.1.0

RUN curl -sL https://deb.nodesource.com/setup_14.x | bash -
RUN apt-get update -qq && apt-get install -qq --no-install-recommends \
    nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g yarn@1
RUN gem install nokogiri
RUN gem install puma

WORKDIR /docai-rails
COPY Gemfile /docai-rails/Gemfile
COPY Gemfile.lock /docai-rails/Gemfile.lock
RUN bundle install
COPY . /docai-rails

# RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rake assets:precompile
#CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

