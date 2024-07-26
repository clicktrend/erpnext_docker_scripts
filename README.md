ERPNext Bash Scripts For Easy Docker Compose Setup
==================================================

Easy to use for my own purpose.

Installation Steps
------------------

Clone project and start installation.

1. Make script folder executable

    chmod +x scripts/*

2. Setup project 
    
    scripts/setup.sh

3. Setup traefik 
    
    scripts/traefik-setup.sh

Go to domain you entered and login with "admin" and password you set!

4. Start traefik

    scripts/traefik-docker.sh up

    # other tasks
    scripts/traefik-docker.sh down
    scripts/traefik-docker.sh logs

5. Setup mariadb

    scripts/mariadb-setup.sh

6. Start mariadb

    scripts/mariadb-docker.sh up

    # other tasks
    scripts/mariadb-docker.sh down
    scripts/mariadb-docker.sh logs

7. Initial Setup for ERPNext

    scripts/erpnext-setup.sh

8. Start ERPNext for first time

    scripts/erpnext-docker.sh up

    # other tasks
    scripts/erpnext-docker.sh down
    scripts/erpnext-docker.sh logs

9. Initial creation of ERPNext site after containers has started with step 8.

    scripts/erpnext-create-site.sh

10. Build custom docker image

    scripts/erpnext-custom-setup.sh

If apps.json doesn't exist in .configs directory template will be copied from .frappe_docker directory.
Change apps.json and run command again.

Deploy Strategy
---------------



Helper
------

Use this command to run bench in backend. Container backend must be running

    scripts/erpnext-backend.sh bench