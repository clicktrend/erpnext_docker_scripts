# ERPNext Bash Scripts for Easy Docker Compose Setup

This collection of bash scripts simplifies the setup of ERPNext using Docker Compose. It will create the `.scripts` directory and all necessary environment files.

## Installation

### Clone the Project and Start Installation

Feel free to use any location. Home directory is fine.

```bash
git clone https://github.com/clicktrend/erpnext_docker_scripts.git
cd erpnext_docker_scripts
```

### Make Script Folder Executable

```bash
chmod +x scripts/*
```

### Setup Project

```bash
scripts/setup.sh
```

After the first run, the `.env` file is created. Edit this file if needed and change `INSTALLED` to `true`. Run the script again:

```bash
scripts/setup.sh
```

`.configs` directory will be created. Most files will be created inside this directory in the next steps. Project `frappe_docker`
will be cloned into `.frappe_docker`.

## Setup Traefik

### Run Traefik Setup

```bash
scripts/traefik-setup.sh
```

Change your DNS to the site you entered.

### Start Traefik

```bash
scripts/traefik-docker.sh up
```
```bash
# Other tasks
scripts/traefik-docker.sh down
scripts/traefik-docker.sh logs
```

Go to the Traefik dashboard with the domain you entered and log in with "admin" and the password you set!

## Setup MariaDB

### Run MariaDB Setup

```bash
scripts/mariadb-setup.sh
```

### Start MariaDB

```bash
scripts/mariadb-docker.sh up
```
```bash
# Other tasks
scripts/mariadb-docker.sh down
scripts/mariadb-docker.sh logs
```

## Initial Setup for ERPNext

### Run ERPNext Setup

```bash
scripts/erpnext-setup.sh
```

### Start ERPNext for the First Time

```bash
scripts/erpnext-docker.sh up
```
```bash
# Other tasks
scripts/erpnext-docker.sh down
scripts/erpnext-docker.sh logs
```

Check the Traefik dashboard to see if the router has started.

### Initial Creation of ERPNext Site After Containers Have Started (see previous setp)

```bash
scripts/erpnext-create-site.sh
```

## Build Custom Docker Image

### Setup Custom Docker Image

```bash
scripts/erpnext-custom-setup.sh
```

### Start Custom ERPNext (Shutdown Containers if Running)

```bash
scripts/erpnext-docker.sh down
scripts/erpnext-custom-docker.sh up
```

If `apps.json` does not exist in the `.configs` directory, a template will be copied from the `.frappe_docker` directory. Change `apps.json` and run the command again.

## Deployment Strategy with HRMS example

Depending on your installation, install apps and migrate the system. See the Helper section.
Use domain you entered with `--site` parameter.

1. Change `apps.json`
2. Change `ERPNEXT_CUSTOM_TAG` in `.env`
3. Run `scripts/erpnext-custom-setup.sh`
4. Run `scripts/erpnext-custom-docker.sh up`
5. Run `scripts/erpnext-backend.sh bench --site one.example.com install-app hrms`
6. Run `scripts/erpnext-backend.sh bench --site one.example.com migrate`
7. Run `scripts/erpnext-backend.sh bench --site one.example.com build`
8. Stop and start containers `scripts/erpnext-custom-docker.sh down` and `scripts/erpnext-custom-docker.sh up`

## Helper

Use this command to run `bench` in the backend. The `backend` container must be running.

```bash
scripts/erpnext-backend.sh bench
# Examples
scripts/erpnext-backend.sh bench --site one.example.com install-app hrms
scripts/erpnext-backend.sh bench --site one.example.com migrate
scripts/erpnext-backend.sh bench --site one.example.com build
scripts/erpnext-backend.sh bench --site one.example.com list-apps
```

## Backup

To backup run manually `scripts/erpnext-backup.sh`.
Or add this line to cronjob of the server.

```bash
0 */6 * * * /path_to/scripts/erpnext-backup.sh > /dev/null
```

To activate restic edit backup section in `.env`, uncomment command lines from `resources/backup-job.yaml` and rerun `scripts/erpnext-setup.sh` and `scripts/erpnext-custom-setup.sh`
