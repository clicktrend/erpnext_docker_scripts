# Vererbung vom Original "base"-Image
FROM base:latest

# Setze den Benutzer auf root, um Änderungen vorzunehmen
USER root

# Installiere zusätzliche Abhängigkeiten für deine App
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Beispiel: Weitere Systempakete
    libxml2-dev libxslt-dev \
    && rm -rf /var/lib/apt/lists/*

# Wechsel zurück zum Benutzer "frappe"
USER frappe

# Installiere Python-Abhängigkeiten für Apps
RUN cd /home/frappe/frappe-bench/apps && \
    for app in $(ls -d */); do \
        if [ -f "$app/requirements.txt" ]; then \
            echo "Installing dependencies for $app..."; \
            /home/frappe/frappe-bench/env/bin/pip install --no-cache-dir -r "$app/requirements.txt"; \
        else \
            echo "No requirements.txt found for $app, skipping..."; \
        fi \
    done

# Arbeitsverzeichnis setzen (falls nötig)
WORKDIR /home/frappe/frappe-bench

# Standardbefehl beibehalten
CMD [ \
    "/home/frappe/frappe-bench/env/bin/gunicorn", \
    "--chdir=/home/frappe/frappe-bench/sites", \
    "--bind=0.0.0.0:8000", \
    "--threads=4", \
    "--workers=2", \
    "--worker-class=gthread", \
    "--worker-tmp-dir=/dev/shm", \
    "--timeout=120", \
    "--preload", \
    "frappe.app:application" \
]
