#
# Build image
#
FROM debian:buster-slim AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        libmodule-build-perl \
        libtitanium-perl \
        libcgi-application-plugin-authentication-perl \
        libcgi-application-plugin-tt-perl \
        libdbd-pg-perl \
        libspreadsheet-xlsx-perl \
        libwww-curl-perl \
        libjson-perl \
        libfile-mimeinfo-perl \
        libxml-twig-perl \
        libstatistics-r-perl \
        r-base-core \
        r-cran-rcurl && \
    rm -rf /var/lib/apt/lists/*

# Build and install TIDES
RUN git clone https://github.com/knowsyn/TIDES.git && \
    cd TIDES && \
    perl Build.PL && \
    ./Build install

# Build and install disambiguateR
RUN git clone https://github.com/hughsalamon/disambiguateR.git && \
    R CMD build disambiguateR && \
    R CMD INSTALL disambiguateR_*.tar.gz && \
    R --vanilla -e 'library(disambiguateR); updateHLAdata()'

#
# Final image
#
FROM debian:buster-slim
LABEL maintainer="Ken Yamaguchi <ken@knowledgesynthesis.com>"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        apache2 \
        ssl-cert \
        libtitanium-perl \
        libcgi-application-plugin-authentication-perl \
        libcgi-application-plugin-tt-perl \
        libdbd-pg-perl \
        libspreadsheet-xlsx-perl \
        libwww-curl-perl \
        libjson-perl \
        libfile-mimeinfo-perl \
        libxml-twig-perl \
        libstatistics-r-perl \
        r-base-core \
        r-cran-rcurl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=build /usr/local /usr/local
COPY --from=build /var/www/html /var/www/html
COPY --from=build /TIDES/tides.conf /etc/apache2/sites-available
COPY --from=build /TIDES/docker-entrypoint.sh /usr/local/bin

RUN ln -s /usr/local/bin/tides /usr/lib/cgi-bin && \
    a2ensite tides && \
    a2dissite 000-default.conf && \
    a2enmod cgid && \
    a2enmod ssl && \
    ln -sf /dev/stdout /var/log/apache2/access.log && \
    ln -sf /dev/stderr /var/log/apache2/error.log && \
    ln -sf /dev/stdout /var/log/apache2/ssl_access.log && \
    ln -sf /dev/stderr /var/log/apache2/ssl_error.log

EXPOSE 443
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/sbin/apachectl", "-D", "FOREGROUND"]
