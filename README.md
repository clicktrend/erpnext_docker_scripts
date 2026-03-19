# ERPNext Docker Scripts

A collection of bash scripts to deploy and manage ERPNext on Docker Compose. The scripts handle the full lifecycle — from initial setup to custom image builds and deployments.

## Prerequisites

Install Docker Engine on Ubuntu: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

## Initial Setup

**1. Clone and prepare**

```bash
git clone https://github.com/clicktrend/erpnext_docker_scripts.git
cd erpnext_docker_scripts
chmod +x scripts/*
```

**2. Initialize the project**

```bash
scripts/setup.sh
```

On first run, a `.env` file is created. Review and adjust the values, then set `INSTALLED=true` and run the script again:

```bash
scripts/setup.sh
```

This creates the `.configs` directory and clones `frappe_docker` into `.frappe_docker`.

---

## Stack Setup

The deployment consists of three independent stacks that must be set up in order.

### 1. Traefik (Reverse Proxy)

```bash
scripts/traefik-setup.sh       # configure domain, email, and admin password
scripts/traefik-docker.sh up   # start Traefik
```

Point your DNS to the domain you entered. The Traefik dashboard is available at that domain — log in with `admin` and the password you set.

### 2. MariaDB

```bash
scripts/mariadb-setup.sh       # generate database password
scripts/mariadb-docker.sh up   # start MariaDB
```

> To reinstall from scratch, delete the MariaDB volume before starting.

### 3. ERPNext

```bash
scripts/erpnext-setup.sh       # generate ERPNext configuration
scripts/erpnext-docker.sh up   # start ERPNext containers
scripts/erpnext-create-site.sh # create the ERPNext site (first time only)
```

Verify in the Traefik dashboard that the ERPNext router has been registered.

---

## Custom Image

Use a custom image to include additional Frappe apps (defined in `apps.json`).

```bash
scripts/erpnext-custom-setup.sh   # build the custom image and generate compose config
scripts/erpnext-docker.sh down
scripts/erpnext-custom-docker.sh up
```

---

## Deployment

To release a new version:

1. Pull latest scripts and update the frappe_docker fork:
   ```bash
   scripts/update.sh
   ```
2. Update `apps.json` if app versions changed
3. Bump `ERPNEXT_CUSTOM_TAG` in `.env`
4. Build and regenerate the compose config:
   ```bash
   scripts/erpnext-custom-setup.sh
   ```
5. Restart ERPNext:
   ```bash
   scripts/erpnext-custom-docker.sh restart
   ```
6. Run migrations and rebuild assets:
   ```bash
   scripts/erpnext-backend.sh bench migrate
   scripts/erpnext-backend.sh bench build
   ```
7. Restart again to apply the build:
   ```bash
   scripts/erpnext-custom-docker.sh restart
   ```

---

## Stack Management

Each stack supports `up`, `down`, `logs`, and `restart`:

```bash
scripts/traefik-docker.sh up|down|logs|restart
scripts/mariadb-docker.sh up|down|logs|restart
scripts/erpnext-custom-docker.sh up|down|logs|restart
```

---

## Running Bench Commands

Use `erpnext-backend.sh` to run `bench` inside the running backend container:

```bash
scripts/erpnext-backend.sh bench --site erp.example.com list-apps
scripts/erpnext-backend.sh bench --site erp.example.com install-app hrms
scripts/erpnext-backend.sh bench --site erp.example.com migrate
scripts/erpnext-backend.sh bench --site erp.example.com build
```

