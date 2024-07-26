ERPNext Bash Scripts For Easy Docker Compose Setup
==================================================

Easy to use for my own purpose. It will create .scripts directory and all necessary env files.

Installation Steps
------------------

Clone project and start installation.

    https://github.com/clicktrend/erpnext_docker_scripts.git
    cd erpnext_docker_scripts

Make script folder executable

    chmod +x scripts/*

Setup project 
    
    scripts/setup.sh

After first run .env is created. Edit file if needed and change INSTALLED to true.
Run script again

    scripts/setup.sh

Setup traefik 
    
    scripts/traefik-setup.sh

Change your DNS to site you entered.

Start traefik

    scripts/traefik-docker.sh up
    // other tasks
    scripts/traefik-docker.sh down
    scripts/traefik-docker.sh logs

Go to Traefik dashboard with domain you entered and login with "admin" and password you set!

Setup mariadb

    scripts/mariadb-setup.sh

Start mariadb

    scripts/mariadb-docker.sh up
    // other tasks
    scripts/mariadb-docker.sh down
    scripts/mariadb-docker.sh logs

Initial Setup for ERPNext

    scripts/erpnext-setup.sh

Start ERPNext for first time

    scripts/erpnext-docker.sh up
    // other tasks
    scripts/erpnext-docker.sh down
    scripts/erpnext-docker.sh logs

Check traefik dashboard if router has started.

Initial creation of ERPNext site after containers has started with step 8.

    scripts/erpnext-create-site.sh

Build custom docker image

    scripts/erpnext-custom-setup.sh

Start ERPNext custom (shutdown containers if running)

    scripts/erpnext-docker.sh down
    scripts/erpnext-custom-docker.sh up

If apps.json doesn't exist in .configs directory template will be copied from .frappe_docker directory.
Change apps.json and run command again.

Deploy Strategy
---------------

1. Change apps.json
2. Change ERPNEXT_CUSTOM_TAG in .env
3. Run scripts/erpnext-custom-setup.sh
4. Run scripts/erpnext-custom-docker.sh up

Depending on your installation install apps, migrate system. See Helper section.

Helper
------

Use this command to run bench in backend. Container backend must be running

    scripts/erpnext-backend.sh bench
    // e.g.
    scripts/erpnext-backend.sh bench --site one.example.com install-app hrms