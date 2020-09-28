### Build and install packages
FROM python:3.8 as build-python

RUN apt-get -y update \
  && apt-get install -y gettext \
  # Cleanup apt cache
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt /app/
WORKDIR /app
RUN pip install -r requirements.txt

### Final image
FROM python:3.8-slim

RUN groupadd --system saleor && useradd --system --gid saleor saleor

RUN apt-get update \
  && apt-get install -y \
  libxml2 \
  libssl1.1 \
  libcairo2 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libgdk-pixbuf2.0-0 \
  shared-mime-info \
  mime-support \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*


# Trivy Vulnerability scan. Fail if any HIGH or CRITICAL vulnerabilities
# https://github.com/aquasecurity/trivy
RUN apt-get install -y curl \
  && curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/master/contrib/install.sh | sh -s -- -b /usr/local/bin \
  && trivy filesystem --exit-code 1 --severity HIGH,CRITICAL --no-progress /

RUN mkdir -p /app/media /app/static \
  && chown -R saleor:saleor /app/

COPY --from=build-python /usr/local/lib/python3.8/site-packages/ /usr/local/lib/python3.8/site-packages/
COPY --from=build-python /usr/local/bin/ /usr/local/bin/
COPY . /app
WORKDIR /app

ARG ALLOWED_CLIENT_HOSTS
ENV ALLOWED_CLIENT_HOSTS ${ALLOWED_CLIENT_HOSTS:-example.com}

ARG STATIC_URL
ENV STATIC_URL ${STATIC_URL:-/static/}
ARG SECRET_KEY
ENV SECRET_KEY ${SECRET_KEY:-dummy}

RUN chmod -R 755 /app/ && \
  SECRET_KEY=${SECRET_KEY} STATIC_URL=${STATIC_URL} python3 manage.py collectstatic --no-input

EXPOSE 8000
ENV PYTHONUNBUFFERED 1

CMD ["gunicorn", "--bind", ":8000", "--workers", "4", "--worker-class", "uvicorn.workers.UvicornWorker", "saleor.asgi:application"]
