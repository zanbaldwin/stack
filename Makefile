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
