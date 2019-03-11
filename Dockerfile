FROM python:3.6

ENV NODE_VERSION 10.15.0
ENV NODE_DOWNLOAD_SHA f0b4ff9a74cbc0106bbf3ee7715f970101ac5b1bbe814404d7a0673d1da9f674  
ENV NODE_DOWNLOAD_URL https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz

RUN curl -SL "$NODE_DOWNLOAD_URL" --output nodejs.tar.gz \
    && echo "$NODE_DOWNLOAD_SHA nodejs.tar.gz" | sha256sum -c - \
    && tar -xzf "nodejs.tar.gz" -C /usr/local --strip-components=1 \
    && rm nodejs.tar.gz \
    && ln -s /usr/local/bin/node /usr/local/bin/nodejs 

RUN apt-get update && \
    apt install -y software-properties-common dirmngr && \
    apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xF1656F24C74CD1D8 && \
    add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://suro.ubaya.ac.id/mariadb/repo/10.3/debian stretch main' && \
    apt-get update && \
    apt-get install -y libpython3.6-dev libmariadb-dev libxml2-dev libxslt1-dev libgv-python graphviz

# Apache configuration for non-root users
EXPOSE 8080

# Create a virtualenv for the application dependencies
RUN virtualenv /venv

# Set virtualenv environment variables. This is equivalent to running
# source /env/bin/activate. This ensures the application is executed within
# the context of the virtualenv and will have access to its dependencies.
ENV VIRTUAL_ENV /venv
ENV PATH /venv/bin:$PATH

# replace standard mod_wsgi with one compiled for Python 3
RUN pip install --no-cache-dir --upgrade gunicorn

# install the application
COPY ./dist/kiwitcms-*.tar.gz /Kiwi/
RUN pip install --no-cache-dir /Kiwi/kiwitcms-*.tar.gz

# install DB requirements b/c the rest should already be installed
COPY ./requirements/ /Kiwi/requirements/
RUN pip install --no-cache-dir -r /Kiwi/requirements/mariadb.txt

# install npm dependencies
COPY package.json /Kiwi/
RUN cd /Kiwi/ && npm install && \
    find ./node_modules -type d -empty -delete

COPY ./manage.py /Kiwi/
COPY ./etc/kiwitcms/ssl/ /Kiwi/ssl/
RUN sed -i "s/tcms.settings.devel/tcms.settings.product/" /Kiwi/manage.py

# create a mount directory so we can properly set ownership for it
RUN mkdir /Kiwi/uploads

# compile translations
RUN /Kiwi/manage.py compilemessages

# collect static files
RUN /Kiwi/manage.py collectstatic --noinput

# from now on execute as non-root
RUN chown -R 1001 /Kiwi/ /venv/ \
    /etc/pki/tls/certs/localhost.crt /etc/pki/tls/private/localhost.key
USER 1001

CMD exec gunicorn tcms.wsgi:application --bind 0.0.0.0:8080 --workers 4
