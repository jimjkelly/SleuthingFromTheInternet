FROM ruby:2.2.1

# Never ask for confirmations
ENV DEBIAN_FRONTEND noninteractive

# Install System Dependencies
RUN apt-get update && apt-get install -y \
  build-essential \
  libpq-dev \
  software-properties-common \
  --no-install-recommends

ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
ENV RAILS_ENV development

# Prepare application Directory
RUN mkdir /app
WORKDIR /app

# Install Application Dependencies
ADD Gemfile /app/Gemfile
ADD Gemfile.lock /app/Gemfile.lock
RUN bundle install --path vendor/bundle

ADD . /app

CMD bundle exec rackup config.ru -p 4567
