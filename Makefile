
PROJECT_NAME=nationbuilder_app
CONTAINER_NAME=nationbuilderapp

# Always run docker-compose with the --project-name flag, or you won't be
# able to correctly base off of the main image for a testing image.
COMPOSE=docker-compose --project-name $(CONTAINER_NAME)

# State tracking, to avoid rebuilding the container on every run.
SENTINEL_DIR=.sentinel
SENTINEL_CONTAINER_CREATED=$(SENTINEL_DIR)/.test-container
SENTINEL_CONTAINER_RUNNING=$(SENTINEL_DIR)/.container-up

###############
# Local Image #
###############

$(SENTINEL_CONTAINER_CREATED): requirements*.txt Dockerfile manage.py */static/*
	mkdir -p $(@D)
	$(COMPOSE) build
	@# Start the DB right away to help avoid a race condition
	$(COMPOSE) up -d db
	until docker exec ${CONTAINER_NAME}_db_1 pg_isready; do sleep 1; done
	touch $@


.PHONY: migrations
migrations: ##[dev utils] Generate django migrations (mange.py makemigrations)
migrations: test-container
	$(COMPOSE) run --rm app python manage.py makemigrations

.PHONY: test-container
test-container: ##[local image] Create a container using docker-compose
test-container: $(SENTINEL_CONTAINER_CREATED)

.PHONY: bash
bash: ##[dev utils] Get a bash shell in your container
bash: test-container
	$(COMPOSE) run --service-ports --rm app /bin/bash

.PHONY: startapp
startapp: ##[dev utils] Shortcut to add a new app to your project.
startapp:
ifdef APP
	mkdir ${PROJECT_NAME}/${APP}
	$(COMPOSE) run --rm app python manage.py startapp ${APP} ${PROJECT_NAME}/${APP}
	@echo "Don't forget to add ${PROJECT_NAME}.${APP} to your INSTALLED_APPS and run make migrations."
else
	@echo "Usage: make startapp APP='my_app_name'"
endif

.PHONY: run
run: ##[testing] Run your app
run: test-container
	$(COMPOSE) run --service-ports --rm app ./activator run

###########
# Running #
###########
.PHONY: migrate
migrate: ##[running] Run the migrations
migrate: up
	$(COMPOSE) run --rm app python manage.py migrate

$(SENTINEL_CONTAINER_RUNNING): $(SENTINEL_CONTAINER_CREATED)
	mkdir -p $(@D)
	$(COMPOSE) up -d app
	touch $@

.PHONY: up
up: ##[running] Start your app with docker-compose
up: test-container $(SENTINEL_CONTAINER_RUNNING)

.PHONY: runserver
runserver: ##[dev utils] Run the django dev server
runserver: $(SENTINEL_CONTAINER_CREATED)
	${COMPOSE} run --service-ports --rm app

.PHONY: down
down: ##[running] Stop the app and dependent containers
down:
	$(COMPOSE) stop
	rm -f $(SENTINEL_CONTAINER_RUNNING)

###########
# Cleanup #
###########

.PHONY: clean
clean: ##[clean up] Stop your containers and delete sentinel files.
clean: ##[clean up] Will cause your containers to get rebuilt.
clean: down
	rm -f $(TEST_OUTPUT)
	rm -f $(COVERAGE_OUTPUT)
	rm -rf $(COVERAGE_HTML_DIR)
	find . -type f -name '*.pyc' -delete
	rm -rf $(SENTINEL_DIR)


.PHONY: teardown
teardown:: ##[clean up] Stop & delete all containers
teardown::
	$(COMPOSE) kill
	$(COMPOSE) rm -f -v
