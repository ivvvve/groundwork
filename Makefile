#* Variables
SHELL := /usr/bin/env bash
PYTHON := python


#* Poetry

.PHONY: poetry-download
poetry-download:
	curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/install-poetry.py | $(PYTHON) -

.PHONY: poetry-remove
poetry-remove:
	curl -sSL https://raw.githubusercontent.com/python-poetry/poetry/master/install-poetry.py | $(PYTHON) - --uninstall


#* Installation

.PHONY: install
install:
	poetry install -n
	yarn

.PHONY: pre-commit-install
pre-commit-install:
	poetry run pre-commit install

.PHONY: migrate
migrate:
	poetry run python manage.py migrate

.PHONY: bootstrap
bootstrap: poetry-download install pre-commit-install migrate
	touch local.py


#* Formatters

.PHONY: codestyle
codestyle:
	poetry run pyupgrade --exit-zero-even-if-changed --py38-plus **/*.py
	poetry run isort --settings-path pyproject.toml ./
	poetry run black --config pyproject.toml ./
	yarn prettier --write .

.PHONY: formatting
formatting: codestyle


#* Documentation

.PHONY: python-api-docs
python-api-docs:
	rm -rf docs/api
	mkdir -p docs/api
	poetry run python bin/gendocs.py

.PHONY: component-docs
component-docs:
	rm -rf docs/components
	mkdir -p docs/components
	cp groundwork/**/docs/*.components.md docs/components/

.PHONY: api-docs
api-docs: python-api-docs component-docs

.PHONY: build-docs
build-docs: api-docs
	poetry run mkdocs build -d build/docs

.PHONY: serve-docs
serve-docs: api-docs
	poetry run mkdocs serve -a localhost:8001

.PHONY: deploy-docs
deploy-docs: api-docs
	poetry run mkdocs gh-deploy --force


#* Linting

.PHONY: test
test:
	poetry run pytest -vs -m "not integration_test"
	yarn test

.PHONY: check-codestyle
check-codestyle:
	poetry run isort --diff --check-only --settings-path pyproject.toml ./
	poetry run black --diff --check --config pyproject.toml ./
	poetry run darglint --docstring-style google --verbosity 2 groundwork
	yarn tsc --noemit
	yarn prettier --check .

.PHONY: check-safety
check-safety:
	poetry check
	poetry run safety check --full-report
	poetry run bandit -ll --recursive groundwork tests

.PHONY: lint
lint: check-codestyle check-safety test

.PHONY: ci
ci: lint build-docs build-js build-python
	poetry run pytest
	yarn test


#* Build & release flow

.PHONY: set-release-version
set-release-version:
	npm version --new-version $$(poetry run python bin/get_release_version.py) --no-git-tag-version
	poetry version $$(poetry run python bin/get_release_version.py)

.PHONY: build-js
build-js:
	yarn vite build --mode lib
	yarn vite build --mode bundled
	yarn vite build --mode test-utils
	rm -rf build/ts
	yarn tsc
	node bin/api-extractor.js

.PHONY: build-python
build-python: build-js
	rm -rf groundwork/core/static
	cp -r build/bundled groundwork/core/static
	poetry build
	rm -rf groundwork/core/static

.PHONY: prepare-release
prepare-release: clean-all set-release-version build-js build-python

.PHONY: release
release:
	echo //registry.npmjs.org/:_authToken=$$NPM_TOKEN > ~/.npmrc
	npm publish
	poetry config pypi-token.pypi $$PYPI_TOKEN
	poetry publish



#* Cleaning

.PHONY: pycache-remove
pycache-remove:
	find . | grep -E "(__pycache__|\.pyc|\.pyo$$)" | xargs rm -rf

.PHONY: build-remove
build-remove:
	rm -rf build/ groundwork/core/static/ docs/api/ docs/components/ temp/

.PHONY: clean-all
clean-all: pycache-remove build-remove
