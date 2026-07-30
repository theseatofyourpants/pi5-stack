# Minimal SMB honeypot: impacket's smbserver exposing a read-only "open" share
# named IT-Backups, seeded with honeytoken files (mounted at /share:ro). SMB2 on
# so modern clients enumerate it. The share is bait — no real data, no write path.
FROM python:3.12-slim
RUN pip install --no-cache-dir impacket==0.12.0
# -ip 0.0.0.0 inside the container; the host publishes only on 10.66.66.1.
# -smb2support so Windows/modern clients speak to it. Runs in the foreground.
CMD ["smbserver.py", "-smb2support", "-ip", "0.0.0.0", "IT-Backups", "/share"]
