FROM python:3.12-slim

RUN useradd --system --create-home --uid 10001 collector
WORKDIR /app
COPY server.py /app/server.py
RUN mkdir /data && chown collector:collector /data
ENV PYTHONDONTWRITEBYTECODE=1
USER collector
VOLUME ["/data"]
EXPOSE 8765
ENTRYPOINT ["python", "/app/server.py"]
