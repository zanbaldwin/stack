SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.ONESHELL:
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules
ifeq ($(origin .RECIPEPREFIX), undefined)
  $(error This Make does not support .RECIPEPREFIX; Please use GNU Make 4.0 or later)
endif
.RECIPEPREFIX = >

THIS_MAKEFILE_PATH:=$(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST))
THIS_DIR:=$(shell cd $(dir $(THIS_MAKEFILE_PATH));pwd)
THIS_MAKEFILE:=$(notdir $(THIS_MAKEFILE_PATH))

DB_NAME := "main"
DB_SERVICE := "database"

usage:
> @grep -E '(^[a-zA-Z_-]+:\s*?##.*$$)|(^##)' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.?## "}; {printf "\033[32m %-30s\033[0m%s\n", $$1, $$2}' | sed -e 's/\[32m ## /[33m/'
.PHONY: usage
.SILENT: usage

vars: ## Display Current Variables Set
vars:
> @$(foreach V,$(sort $(.VARIABLES)), $(if $(filter-out environment% default automatic, $(origin $V)),$(warning $V = $(value $V))))
.PHONY: vars
.SILENT: vars

## Building

enable-https: ## Installs an SSL Certificate for the Domain
enable-https:
> export $$(echo "$$(cat "$(THIS_DIR)/.env" | sed 's/#.*//g'| xargs)")
> [ -z "$${DOMAIN}" ] && { echo >&2 "Could not determine domain from environment file."; exit 1; }
> sudo docker-compose -f "$(THIS_DIR)/docker-compose.yaml" down
> sudo mkdir -p "/etc/letsencrypt/challenges"
> sudo docker-compose -f "$(THIS_DIR)/docker-compose.yaml" run -d --name "acme" server nginx -c "/etc/nginx/acme.conf"
> sudo certbot certonly --webroot \
    --webroot-path="/etc/letsencrypt/challenges" \
    --cert-name="$${DOMAIN}" \
    -d "$${DOMAIN}" \
    -d "www.$${DOMAIN}"
> sudo openssl dhparam -out "/etc/letsencrypt/dhparam.pem" 4096
> sudo docker-compose -f "$(THIS_DIR)/docker-compose.yaml" down
.PHONY: enable-https
.SILENT: enable-https

mock-https: ## Mocks an SSL Certificate for Development
mock-https:
> command -v "mkcert" >/dev/null 2>&1 || { echo >&2 "Please install MkCert for Development."; exit 1; }
> export $$(echo "$$(cat "$(THIS_DIR)/.env" | sed 's/#.*//g'| xargs)")
> [ -z "$${DOMAIN}" ] && { echo >&2 "Could not determine domain from environment file."; exit 1; }
> mkdir -p "$(THIS_DIR)/build/ssl/challenges"
> mkdir -p "$(THIS_DIR)/build/ssl/live/$${DOMAIN}"
> (cd "$(THIS_DIR)/build/ssl"; mkcert "localhost" "$${DOMAIN}" "server" "127.0.0.1")
> mkcert \
    -cert-file "$(THIS_DIR)/build/ssl/live/$${DOMAIN}/fullchain.pem" \
    -key-file "$(THIS_DIR)/build/ssl/live/$${DOMAIN}/privkey.pem" \
    "localhost" \
    "127.0.0.1" \
    "$${DOMAIN}" \
    "server" \
    "varnish"
> cp "$$(mkcert -CAROOT)/rootCA.pem" "$(THIS_DIR)/build/ssl/ca.pem"
> mv "$(THIS_DIR)/build/ssl/localhost+3.pem" "$(THIS_DIR)/build/ssl/live/$${DOMAIN}/fullchain.pem"
> cp "$(THIS_DIR)/build/ssl/live/$${DOMAIN}/fullchain.pem" "$(THIS_DIR)/build/ssl/live/$${DOMAIN}/chain.pem"
> mv "$(THIS_DIR)/build/ssl/localhost+3-key.pem" "$(THIS_DIR)/build/ssl/live/$${DOMAIN}/privkey.pem"
> openssl dhparam -out "$(THIS_DIR)/build/ssl/dhparam.pem" 1024
.PHONY: mock-https
.SILENT: mock-https

password: ## Generates a secure, random password for the database
password:
> mkdir -p "$(THIS_DIR)/build/.secrets"
> [ ! -f "$(THIS_DIR)/build/.secrets/dbpass" ] || { \
    echo >&2 "$$(tput setaf 1)A password has already been created. Remove the file \"$(THIS_DIR)/build/.secrets/dbpass\" to try again.$$(tput sgr0)"; \
    echo >&2 "$$(tput setaf 1)Double check that you're NOT REMOVING THE ONLY COPY OF YOUR EXISTING PASSWORD.$$(tput sgr0)"; \
    exit 1; \
}
> touch "$(THIS_DIR)/build/.secrets/dbpass"
> echo "$$(date "+%s.%N" | sha256sum | base64 | head -c 40)" > "$(THIS_DIR)/build/.secrets/dbpass"
> echo >&2 "$$(tput setaf 2)Database password generated and placed in file \"$(THIS_DIR)/build/.secrets/dbpass\".$$(tput sgr0)"
.PHONY: password
.SILENT: password

## Maintenance

renew-certs: ## Re-installs SSL Certificates that near expiry and due for renewal
renew-certs:
> echo >&2 "--------------------------------------------------------------------------------"
> date >&2
> certbot renew
# CRON by default does not set any useful environment variables, Docker Compose
# is installed to a non-standard location so we have to specify that.
> export PATH="$${PATH:-"/bin:/sbin:/usr/bin"}:/usr/local/bin"
# Nginx has to be restarted in order to use the new certificates.
> docker-compose -f "$(THIS_DIR)/docker-compose.yaml" restart server
.PHONY: renew-certs
.SILENT: renew-certs

database-backup: ## Create a backup of the database and upload to S3
database-backup:
# CRON by default does not set any useful environment variables, Docker Compose
# is installed to a non-standard location so we have to specify that.
> export PATH="$${PATH:-"/bin:/usr/bin"}:/usr/local/bin"
# Database backup is meant to be run by CRON and output saved to a log file. Use ANSI only (no colours).
> export DB_DUMP_FILENAME="database-$$(date -u '+%Y%m%dT%H%m%SZ').sql"
> echo >&2 "--------------------------------------------------------------------------------"
> date >&2
> command -v docker >/dev/null 2>&1 || { echo >&2 "Command \"docker\" not found in \$$PATH. Make sure CRON has the correct environment variables set."; exit 1; }
> command -v docker-compose >/dev/null 2>&1 || { echo >&2 "Command \"docker-compose\" not found in \$$PATH. Make sure CRON has the correct environment variables set."; exit 1; }
> command -v bzip2 >/dev/null 2>&1 || { echo >&2 "Command \"bzip2\" not found in \$$PATH. Make sure CRON has the correct environment variables set."; exit 1; }
> docker-compose -f "$(THIS_DIR)/docker-compose.yaml" up -d "$(DB_SERVICE)" || { echo >&2 "Could not bring up Docker service \"$(DB_SERVICE)\"."; exit 2; }
> sleep 10
> docker-compose -f "$(THIS_DIR)/docker-compose.yaml" exec -T -e "MYSQL_PWD=$$(cat '$(THIS_DIR)/build/.secrets/dbpass' | tr -d '\n\r')" "$(DB_SERVICE)" mysqldump -u"root" \
    --add-locks --add-drop-table  --add-drop-trigger \
    --comments  --disable-keys    --complete-insert \
    --hex-blob  --insert-ignore   --quote-names \
    --tz-utc    --triggers        --single-transaction \
    --skip-extended-insert \
    "$(DB_NAME)" > "/tmp/$${DB_DUMP_FILENAME}" || { echo >&2 "Docker could not export database to filesystem dump."; exit 3; }
> export DB_DUMP_COMPRESSED="$${DB_DUMP_FILENAME}.bz2"
> bzip2 --compress --best --stdout < "/tmp/$${DB_DUMP_FILENAME}" > "/tmp/$${DB_DUMP_COMPRESSED}" && { \
    rm "/tmp/$${DB_DUMP_FILENAME}" || true; \
} || { \
    echo >&2 "Could not compress database dump, continuing to upload uncompressed file to S3."; \
    export DB_DUMP_COMPRESSED="$${DB_DUMP_FILENAME}"; \
}
> mkdir -p "$(THIS_DIR)/var/dump" && cp "/tmp/$${DB_DUMP_COMPRESSED}" "$(THIS_DIR)/var/dump/$${DB_DUMP_COMPRESSED}" || { \
    echo >&2 "Could move database dump to \"$(THIS_DIR)/var/dump/$${DB_DUMP_COMPRESSED}\"."; \
    echo >&2 "Please see temporary dump file \"/tmp/$${DB_DUMP_COMPRESSED}\".";
    exit 4;
}
> rm "/tmp/$${DB_DUMP_COMPRESSED}" || true
.PHONY: database-backup
.SILENT: database-backup
