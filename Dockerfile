ARG PHP_VERSION=8.1

FROM docker.io/library/php:$PHP_VERSION-apache

ENV WEBTREES_HOME="/var/www/webtrees"
ENV COCKROACH_CERT="https://cockroachlabs.cloud/clusters/ddfd014b-9ab5-4e6b-a728-9b4a3f271ed9/cert"
WORKDIR $WEBTREES_HOME

# install pre-reqs
RUN apt-get update \
 && apt-get install -y \
    curl \
    libmagickwand-dev \
    libpq-dev \
    libzip-dev \
    mariadb-client \
    python3 \
    unzip \
    --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*
# install php extensions
RUN pecl install imagick \
 && docker-php-ext-enable imagick \
 && docker-php-ext-configure gd --with-freetype --with-jpeg \
 && docker-php-ext-install -j"$(nproc)" pdo pdo_mysql pdo_pgsql zip intl gd exif
# remove old apt stuff
RUN apt-get purge gcc g++ make -y \
 && apt-get autoremove -y \
 && apt-get clean \
 && rm -rf /var/tmp/* /etc/apache2/sites-enabled/000-*.conf

# install webtrees and disable version update prompt
# https://www.webtrees.net/index.php/fr/forum/help-for-2-0/36616-email-error-after-update-to-2-0-21#89985
# https://github.com/NathanVaughn/webtrees-docker/issues/88
RUN curl -s -L https://github.com/parrajustin/webtrees/releases/download/2.1.15-psql.3/webtrees-2.1.15-psql.3.zip -o webtrees.zip \
 && unzip -q webtrees.zip -d /var/www/ && rm webtrees.zip \
 && chown -R www-data:www-data ./ \
 && perl -0777 -i -pe "s/private\s+function\s+fetchLatestVersion[\S\s]+?{[\S\s]+?{[\S\s]+?{[\S\s]+?{[\S\s]+?}[\S\s]+?}[\S\s]+?}[\S\s]+?}[\S\s]+?}/private function fetchLatestVersion(): string { return Site::getPreference('LATEST_WT_VERSION'); }/" app/Services/UpgradeService.php \
 && rm -f vendor/egulias/email-validator/src/Validation/MessageIDValidation.php

RUN curl --create-dirs -o /var/postgresql/root.crt -O $COCKROACH_CERT

# enable apache modules
RUN a2enmod rewrite && a2enmod ssl && rm -rf /var/www/html

# copy apache/php configs
COPY .htaccess ./
COPY apache/ /etc/apache2/sites-available/

# entrypoint
COPY docker-entrypoint.py /

# healthcheck
COPY docker-healthcheck.sh /
RUN chmod +x /docker-healthcheck.sh

# final Docker config
EXPOSE 80 443
VOLUME ["$WEBTREES_HOME/data", "$WEBTREES_HOME/media"]

HEALTHCHECK CMD /docker-healthcheck.sh
ENTRYPOINT ["python3", "/docker-entrypoint.py"]
