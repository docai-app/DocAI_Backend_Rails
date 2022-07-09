FROM ruby:3.1.0
WORKDIR /app
COPY Gemfile /app/Gemfile
COPY Gemfile.lock /app/Gemfile.lock
RUN bundle install
COPY . /app
# RUN SECRET_KEY_BASE=1 RAILS_ENV=production bundle exec rake assets:precompile
#CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

