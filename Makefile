BASE := $(shell /bin/pwd)

################# 
#  Python vars	#
################# 

VERSION ?= 3.6
SERVICE ?= service_not_defined
VENV ?= ${SERVICE}/.venv
VENV_LIBS ?= $(VENV)/lib/python${VERSION}/site-packages
CACHE ?= ${HOME}/.pip_cache/

############# 
#  SAM vars	#
############# 

TEMPLATE ?= template.yaml
S3_BUCKET ?= bucket_not_defined
NETWORK = ""

target:
	$(info ${HELP_MESSAGE})
	@exit 0

clean: ##=> Deletes current virtual env environment, dev files and build
	$(info [*] Who needs all that anyway? Destroying environment....)
	rm -rf ./$(VENV)
	rm -rf ./$(SERVICE)/dev
	rm -rf ./${SERVICE}.zip

all: clean build

# Credits python-with-packages PR
build: _check_service_definition ##=> Builds package using Docker Lambda container
	$(info [*] Cleaning up local dev/builds before build task...)
	@$(MAKE) clean SERVICE="${SERVICE}"
	$(info [+] Packaging service '$(SERVICE)' using Docker Lambda -- This may take a while...)
	docker run -v $$PWD:/var/task -it lambci/lambda:build-python3.6 /bin/bash -c 'make _package SERVICE="${SERVICE}"'

build-dev: _check_service_definition _clone_service_to_dev ##=> creates dev folder and install dependencies (requirements.txt) into dev/ folder for hot-reloading
	$(info [+] Installing dependencies into dev/)
	pip${VERSION} install \
		--isolated \
		--disable-pip-version-check \
		-Ur $(SERVICE)/requirements.txt -t ${SERVICE}/dev/

deploy: _check_template_definition ##=> Builds, then Packages and Deploys latest service via SAM

ifeq ($(wildcard $(SERVICE).zip/.),)
	$(info [*] No ${SERVICE} build found; Building latest version of '${SERVICE}' service prior to deploy...)
	@$(MAKE) build SERVICE="${SERVICE}"
endif

	$(info [+] [SAM] Packaging '${SERVICE}' service)

	aws cloudformation package \
		--template-file ${TEMPLATE} \
		--output-template-file packaged-template.yaml \
		--s3-bucket $(S3_BUCKET)

	$(info [+] [SAM] Deploying '${SERVICE}' service)

	aws cloudformation deploy \
		--template-file packaged-template.yaml \
		--stack-name ${SERVICE} \
		--capabilities CAPABILITY_IAM

run: _check_template_definition ##=> Run SAM Local API GW and can optionally run new containers connected to a defined network
	@test -z ${NETWORK} \
		&& sam local start-api \
		|| sam local start-api --docker-network ${NETWORK}

############# 
#  Helpers	#
############# 

_check_service_definition:
	$(info [*] Checking whether service $(SERVICE) exists...)

# SERVICE="<name_of_service>" must be passed as ARG for target or else fail
ifndef SERVICE
	$(error [!] SERVICE env not defined...FAIL)
endif

ifeq ($(wildcard $(SERVICE)/.),)
	$(error [!] '$(SERVICE)' folder doesn't exist)
endif

ifeq ($(wildcard $(SERVICE)/requirements.txt),)
	$(error [!] Pip requirements file missing from $(SERVICE) folder...)
endif

_check_template_definition:
	$(info [*] Checking whether SAM template exist)

ifeq ($(wildcard $(TEMPLATE)/.),)
	$(error [!] SAM template '${TEMPLATE}' doesn't exist!)
endif

_bootstrap: _check_service_definition
	$(info [*] Checking whether virtual environment $(VENV) exists...)

ifeq ($(wildcard $(VENV)/.),)
	$(info [+] Creating virtual environment at '$(VENV)')
	python -m venv $(VENV) && mkdir -p $(VENV)/dist
	. $(VENV)/bin/activate && pip${VERSION} install -Ur $(SERVICE)/requirements.txt
else
	$(info [*] Virtual environment exists...ignoring bootstrap task
endif

_clone_service_to_dev:
ifeq ($(wildcard $(SERVICE)/dev/.),)
	$(info [+] Cloning ${SERVICE} directory structure to ${SERVICE}/dev)
	@rsync -a -f "+ */" -f "- *" -f "- dev/" ${SERVICE}/ ${SERVICE}/dev/
	$(info [+] Cloning source files from ${SERVICE} to ${SERVICE}/dev)
	@find ${SERVICE} -type f \
			-not -name "*.pyc" \
			-not -name "*__pycache__" \
			-not -name "requirements.txt" \
			-not -name "event.json" \
			-not -name "dev" | cut -d '/' -f2- > .results.txt
	@while read line; do \
		ln -f ${SERVICE}/$$line ${SERVICE}/dev/$$line; \
	done < .results.txt
else
	$(info [*] '${BASE}/${SERVICE}/dev' structure exists; ignoring cloning stage...)
endif

_check_pip_cache_folder:
ifeq ($(wildcard $(CACHE)/.),)
	$(warning [FIX] Use 'pip download -d <cache_folder> -r requirements.txt' to create a cache folder)
	$(warning [FIX] Then call `make build-dev-offline CACHE=<cache_folder>`)
	$(error [!] Pip cache '$(CACHE)' folder doesn't exist)
endif

_check_dev_definition: _check_service_definition
	$(info [*] Checking whether service $(SERVICE) development build exists...)

ifeq ($(wildcard $(SERVICE)/dev/.),)
	$(warning [FIX] run 'make build-dev SERVICE=$(SERVICE)' to create one")
	$(error [!] '$(SERVICE)' doesn't have development build)
endif

# WARNING: Advanced users only...

################################
#  Virtual env | dev packaging #
################################ 

# Packages lambda function into acceptable ZIP format
_package: _bootstrap 
	$(info [+] Packaging service '$(SERVICE)'...)
	@rm -rf $(VENV)/dist/*
	@rsync -azq \
		--exclude '*.pyc' \
		--exclude '*__pycache__' \
		--exclude 'requirements.txt' \
		--exclude 'event.json' \
		$(VENV_LIBS)/ $(SERVICE)/ $(VENV)/dist/
	$(info [+] Creating '$(SERVICE)' ZIP...")
	@cd $(VENV)/dist && zip -rq -9 "$(BASE)/$(SERVICE).zip" *
	$(info [*] Build complete: $(BASE)/$(SERVICE).zip)

# Create zip straight from `dev`
_zip: _check_dev_definition
	$(info [+] Creating '$(SERVICE)' ZIP...")
	@cd ${SERVICE}/dev && zip -rq -9 "$(BASE)/$(SERVICE).zip" *
	$(info [*] Build complete: $(BASE)/$(SERVICE).zip)

######################### 
#  Long haul flights ;)	#
######################### 

# Builds package using Docker Lambda container but requires CACHE (env) folder
_build-from-pip-cache: _check_service_definition _check_pip_cache_folder 
	$(info [+] Packaging service '$(SERVICE)' using Docker Lambda -- This may take a while...)
	docker run -v $$PWD:/var/task -v ${CACHE}:/root/.pip_cache -it lambci/lambda:build-python3.6 /bin/bash -c 'make _package SERVICE="${SERVICE}"'

# Same as build-dev but requires CACHE (env) folder
_build-dev-from--pip-cache: _check_service_definition _check_pip_cache_folder _clone_service_to_dev 
	$(info [+] Installing dependencies into '${BASE}/${SERVICE}/dev/')
	pip${VERSION} install \
		--isolated \
		--disable-pip-version-check \
		--no-index \
		--find-links ${CACHE} \
		-Ur $(SERVICE)/requirements.txt -t ${SERVICE}/dev/

######################### 
#  Long haul flights ;)	#
######################### 

define HELP_MESSAGE
	Environment variables to be aware of or to hardcode depending on your use case:

	SERVICE
		Default: not_defined
		Info: Environment variable to declare where source code and requirements.txt are
	TEMPLATE
		Default: template.yaml
		Info: SAM Template file to read from (packaging/deploying)
	VERSION
		Default: 3.6
		Info: Python version (only Python 3 supported at this stage)

	Common usage:

	...::: Cleans up the environment - Deletes Virtualenv, ZIP builds and Dev env :::...
	$ make clean SERVICE="slack"

	...::: Creates local dev environment for Python hot-reloading w/ packages:::...
	$ make build-dev SERVICE="email"

	...::: Creates ZIP directly from local dev environment :::...
	$ make _zip SERVICE="email"

	...::: Packages and Deploy SAM using default AWS CLI region :::...
	$ make deploy S3_BUCKET="lessa-demo-bucket"

	...::: Creates ZIP via Docker container (Lambci) :::...
	$ make build SERVICE="email"

	...::: Run SAM Local API Gateway :::...
	$ make run

	Advanced usage:

	...::: Run SAM Local API Gateway within a Docker Network :::...
	$ make run NETWORK="sam-network"

	...::: Creates local dev enviroonment and install dependencies from Pip cache location :::...
	$ make _build-dev-from--pip-cache CACHE="~/.pip_cache/"

	...::: Creates ZIP via Docker container (Lambci) and install dependencies from Pip cache location :::...
	$ make _build-dev-from--pip-cache CACHE="~/.pip_cache/"
endef
