FROM postgres:16-bookworm

ENV PATH="/opt/patroni/bin:/usr/lib/postgresql/16/bin:${PATH}" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

COPY patroni/requirements.txt /tmp/patroni-requirements.txt

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        gcc \
        libpq-dev \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
    && python3 -m venv /opt/patroni \
    && /opt/patroni/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
    && /opt/patroni/bin/pip install --no-cache-dir -r /tmp/patroni-requirements.txt \
    && ln -s /opt/patroni/bin/patroni /usr/local/bin/patroni \
    && ln -s /opt/patroni/bin/patronictl /usr/local/bin/patronictl \
    && rm -rf /var/lib/apt/lists/* /tmp/patroni-requirements.txt

USER postgres

