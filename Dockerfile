FROM ubuntu:jammy

# install required packages
# https://github.com/openssl/openssl#build-and-install
# https://dev.mysql.com/doc/refman/8.0/en/source-installation-prerequisites.html
RUN apt-get update \
    && apt-get install -y wget perl cmake gcc g++ libncurses-dev pkg-config \
    && apt-get install -y dpkg-dev libudev-dev bison \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# install libssl 1.1
#
# MySQL does not support libssl version 3, and in ubuntu:jammy, only libssl-dev version 3 is provided. Therefore, we need to install libssl from the source.
# Once the bug ticket at the following link is resolved, we simply need to install libssl-dev.
# https://bugs.mysql.com/bug.php?id=102405
RUN apt-get update && apt-get install -y perl
ENV OPENSSL_VERSION 1.1.1o
RUN cd /tmp \
    && wget https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz \
    && tar xvzf openssl-${OPENSSL_VERSION}.tar.gz \
    && cd openssl-${OPENSSL_VERSION} \
    && ./config \
    && make \
    && make install \
    && ldconfig

# install mysql-build
RUN cd /tmp \
    && wget https://github.com/kamipo/mysql-build/archive/master.tar.gz \
    && tar xvzf master.tar.gz \
    && mv mysql-build-master /usr/local/mysql-build \
    && rm master.tar.gz

ENV Q4M_PLUGIN q4m
COPY docker/${Q4M_PLUGIN} /usr/local/mysql-build/share/mysql-build/plugins/${Q4M_PLUGIN}
# see ./docker/q4m
COPY ./ /tmp/q4m

# build + install mysql
#
# You can use mysql versions listed here: https://github.com/kamipo/mysql-build/tree/master/share/mysql-build/definitions
ARG MYSQL_VERSION
RUN /usr/local/mysql-build/bin/mysql-build -v ${MYSQL_VERSION} /usr/local/mysql ${Q4M_PLUGIN}
ENV PATH /usr/local/mysql/bin:$PATH

# user, group
RUN mkdir /var/lib/mysql \
    && groupadd mysql \
    && useradd -r -g mysql -s /bin/false mysql \
    && chown -R mysql:mysql /var/lib/mysql

COPY docker/my.cnf /etc/mysql/my.cnf
RUN mysqld --initialize-insecure --user=mysql \
    && mysql_ssl_rsa_setup \
    && mysqld --daemonize --skip-networking --user mysql --socket /tmp/mysql.sock \
    && echo "CREATE USER 'root'@'%'; GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES; " | mysql -uroot -hlocalhost --socket /tmp/mysql.sock \
    && cat /usr/local/mysql/support-files/install-q4m.sql | mysql -uroot -hlocalhost --socket /tmp/mysql.sock \
    && mysqladmin shutdown -uroot --socket /tmp/mysql.sock

EXPOSE 3306
ENTRYPOINT [ "mysqld", "--user=mysql" ]
