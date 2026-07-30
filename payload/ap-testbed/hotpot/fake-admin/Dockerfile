# Fake router/NAS admin login. Stdlib only — no third-party surface to exploit.
FROM python:3.12-slim
COPY app.py /app/app.py
WORKDIR /app
CMD ["python", "-u", "app.py"]
