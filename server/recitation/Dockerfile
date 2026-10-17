FROM python:3.12.14-slim-bookworm@sha256:392307d22300de8b5986851a12d9176dfc0fc073e65bf6523ebd7dcbeb23564e
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /app
COPY server/recitation/requirements-linux.lock /app/requirements-linux.lock
RUN pip install --no-cache-dir --require-hashes -r /app/requirements-linux.lock && useradd --uid 10001 --no-create-home noor
COPY server/recitation /app/server/recitation
COPY content-sources/recitation-word-script.json content-sources/mushaf-snapshot.json.gz /app/content-sources/
COPY ios/Athar/quran.json /app/ios/Athar/quran.json
ENV PYTHONPATH=/app/server/recitation NOOR_CORPUS_ROOT=/app NOOR_MODEL_PATH=/model
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health/ready', timeout=3).read()"
CMD ["python", "-m", "uvicorn", "noor_engine.api:application", "--factory", "--host", "0.0.0.0", "--port", "8080", "--workers", "1", "--ws-max-size", "524288", "--ws-max-queue", "1", "--limit-concurrency", "32", "--backlog", "32", "--no-access-log"]
