FROM python:3.13-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --disable-pip-version-check --root-user-action=ignore -r requirements.txt
COPY helloapp/ helloapp/

FROM base AS test
RUN python -m unittest helloapp.test

FROM base
USER 65534:65534
EXPOSE 8080
CMD ["gunicorn", "--bind=0.0.0.0:8080", "--workers=2", "--worker-tmp-dir=/dev/shm", "--no-control-socket", "--access-logfile=-", "helloapp.app:app"]
