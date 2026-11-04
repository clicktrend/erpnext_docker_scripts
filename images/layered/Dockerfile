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

# Cache-bust arg — ensures frontend is always rebuilt fresh on deploy
ARG CACHEBUST=1

# Build React frontend (adomio workstation SPA)
# Output goes to adomio/public/frontend/ → served via sites/assets/adomio/frontend/
RUN if [ -f /home/frappe/frappe-bench/apps/adomio/frontend/package.json ]; then \
        echo "Building adomio React frontend..." && \
        cd /home/frappe/frappe-bench/apps/adomio/frontend && \
        npm install --no-audit --no-fund && \
        node_modules/.bin/vite build && \
        echo "Frontend build complete."; \
    else \
        echo "No frontend/package.json found, skipping React build."; \
    fi

# Build the erpnext_capture receipt-review SPA (B2C image, app is optional: guarded like adomio above).
# vite.config: outDir ../erpnext_capture/public/frontend, base /assets/erpnext_capture/frontend/ (2026-09-08).
RUN if [ -f /home/frappe/frappe-bench/apps/erpnext_capture/frontend/package.json ]; then \
        echo "Building erpnext_capture frontend..." && \
        cd /home/frappe/frappe-bench/apps/erpnext_capture/frontend && \
        npm install --no-audit --no-fund && \
        node_modules/.bin/vite build && \
        echo "erpnext_capture frontend build complete."; \
    else \
        echo "No erpnext_capture/frontend/package.json found, skipping."; \
    fi

# Raven (B2B, 2026-11-04): its `openai-agents` (unpinned, >=0.17.2) pulls openai 3.x, while ask_alyf's
# langchain-openai and litellm require openai<3. Pin the last openai-agents that accepts openai 2.x and keep
# openai on 2.x. Placed after CACHEBUST so a changed pin applies without a --no-cache base build.
RUN if [ -d /home/frappe/frappe-bench/apps/raven ]; then \
        /home/frappe/frappe-bench/env/bin/pip install --no-cache-dir --no-deps \
            "openai==2.54.0" "openai-agents==0.20.0" && \
        /home/frappe/frappe-bench/env/bin/pip check 2>&1 | grep -iE "openai|agents|langchain|litellm|raven" || true; \
    fi

# Python 3.13 dropped the stdlib `cgi` module; the Shopify client stack (ShopifyAPI/pyactiveresource) still
# imports it on some code paths (install of the ecommerce_integrations fork failed on prod, 2026-09-08).
RUN /home/frappe/frappe-bench/env/bin/pip install --no-cache-dir legacy-cgi

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
