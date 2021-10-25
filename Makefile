# Licensed under the Apache License: http://www.apache.org/licenses/LICENSE-2.0
# For details: https://github.com/nedbat/coveragepy/blob/master/NOTICE.txt

# Makefile for utility work on coverage.py.

help:					## Show this help.
	@echo "Available targets:"
	@grep '^[a-zA-Z]' $(MAKEFILE_LIST) | sort | awk -F ':.*?## ' 'NF==2 {printf "  %-26s%s\n", $$1, $$2}'

clean_platform:                         ## Remove files that clash across platforms.
	@rm -f *.so */*.so
	@rm -rf __pycache__ */__pycache__ */*/__pycache__ */*/*/__pycache__ */*/*/*/__pycache__ */*/*/*/*/__pycache__
	@rm -f *.pyc */*.pyc */*/*.pyc */*/*/*.pyc */*/*/*/*.pyc */*/*/*/*/*.pyc
	@rm -f *.pyo */*.pyo */*/*.pyo */*/*/*.pyo */*/*/*/*.pyo */*/*/*/*/*.pyo

clean: clean_platform                   ## Remove artifacts of test execution, installation, etc.
	@echo "Cleaning..."
	@-pip uninstall -yq coverage
	@rm -f *.pyd */*.pyd
	@rm -rf build coverage.egg-info dist htmlcov
	@rm -f *.bak */*.bak */*/*.bak */*/*/*.bak */*/*/*/*.bak */*/*/*/*/*.bak
	@rm -f *$$py.class */*$$py.class */*/*$$py.class */*/*/*$$py.class */*/*/*/*$$py.class */*/*/*/*/*$$py.class
	@rm -f coverage/*,cover
	@rm -f MANIFEST
	@rm -f .coverage .coverage.* coverage.xml .metacov*
	@rm -f .tox/*/lib/*/site-packages/zzz_metacov.pth
	@rm -f */.coverage */*/.coverage */*/*/.coverage */*/*/*/.coverage */*/*/*/*/.coverage */*/*/*/*/*/.coverage
	@rm -f tests/covmain.zip tests/zipmods.zip tests/zip1.zip
	@rm -rf doc/_build doc/_spell doc/sample_html_beta
	@rm -rf tmp
	@rm -rf .cache .pytest_cache .hypothesis
	@rm -rf tests/actual
	@-make -C tests/gold/html clean

sterile: clean                          ## Remove all non-controlled content, even if expensive.
	rm -rf .tox


CSS = coverage/htmlfiles/style.css
SCSS = coverage/htmlfiles/style.scss

css: $(CSS)				## Compile .scss into .css.
$(CSS): $(SCSS)
	pysassc --style=compact $(SCSS) $@
	cp $@ tests/gold/html/styled

LINTABLE = coverage tests igor.py setup.py __main__.py

lint:					## Run linters and checkers.
	tox -q -e lint

test:
	tox -q -e py39 $(ARGS)

PYTEST_SMOKE_ARGS = -n 6 -m "not expensive" --maxfail=3 $(ARGS)

smoke: 					## Run tests quickly with the C tracer in the lowest supported Python versions.
	COVERAGE_NO_PYTRACER=1 tox -q -e py39 -- $(PYTEST_SMOKE_ARGS)

pysmoke: 				## Run tests quickly with the Python tracer in the lowest supported Python versions.
	COVERAGE_NO_CTRACER=1 tox -q -e py39 -- $(PYTEST_SMOKE_ARGS)

metasmoke:
	COVERAGE_NO_PYTRACER=1 ARGS="-e py39" make clean metacov metahtml

# Coverage measurement of coverage.py itself (meta-coverage). See metacov.ini
# for details.

metacov:				## Run meta-coverage, measuring ourself.
	COVERAGE_COVERAGE=yes tox -q $(ARGS)

metahtml:				## Produce meta-coverage HTML reports.
	python igor.py combine_html

upgrade: export CUSTOM_COMPILE_COMMAND=make upgrade
upgrade: 				## update the *.pip files with the latest packages satisfying *.in files
	pip install -q -r requirements/pip-tools.pip
	pip-compile --upgrade -o requirements/pip-tools.pip requirements/pip-tools.in
	pip-compile --upgrade -o requirements/pip.pip requirements/pip.in
	pip-compile --upgrade -o requirements/pytest.pip requirements/pytest.in
	pip-compile --upgrade -o requirements/ci.pip requirements/ci.in
	pip-compile --upgrade -o requirements/dev.pip requirements/dev.in
	pip-compile --upgrade -o doc/requirements.pip doc/requirements.in

# Kitting

kit:					## Make the source distribution.
	python -m build

kit_upload:				## Upload the built distributions to PyPI.
	twine upload --verbose dist/*

test_upload:				## Upload the distributions to PyPI's testing server.
	twine upload --verbose --repository testpypi dist/*

kit_local:
	# pip.conf looks like this:
	#   [global]
	#   find-links = file:///Users/ned/Downloads/local_pypi
	cp -v dist/* `awk -F "//" '/find-links/ {print $$2}' ~/.pip/pip.conf`
	# pip caches wheels of things it has installed. Clean them out so we
	# don't go crazy trying to figure out why our new code isn't installing.
	find ~/Library/Caches/pip/wheels -name 'coverage-*' -delete

download_kits:				## Download the built kits from GitHub.
	python ci/download_gha_artifacts.py nedbat/coveragepy

check_kits:				## Check that dist/* are well-formed.
	python -m twine check dist/*

build_ext:
	python setup.py build_ext

# Documentation

DOCBIN = .tox/doc/bin
SPHINXOPTS = -aE
SPHINXBUILD = $(DOCBIN)/sphinx-build $(SPHINXOPTS)
SPHINXAUTOBUILD = $(DOCBIN)/sphinx-autobuild -p 9876 --ignore '.git/**' --open-browser
WEBHOME = ~/web/stellated
WEBSAMPLE = $(WEBHOME)/files/sample_coverage_html
WEBSAMPLEBETA = $(WEBHOME)/files/sample_coverage_html_beta

$(DOCBIN):
	tox -q -e doc --notest

cmd_help: $(DOCBIN)
	@for cmd in annotate combine debug erase html json report run xml; do \
		echo > doc/help/$$cmd.rst; \
		echo ".. This file is auto-generated by \"make dochtml\", don't edit it manually." >> doc/help/$$cmd.rst; \
		echo >> doc/help/$$cmd.rst; \
		echo ".. code::" >> doc/help/$$cmd.rst; \
		echo >> doc/help/$$cmd.rst; \
		echo "    $$ coverage $$cmd --help" >> doc/help/$$cmd.rst; \
		$(DOCBIN)/python -m coverage $$cmd --help | \
		sed \
			-e 's/__main__.py/coverage/' \
			-e '/^Full doc/d' \
			-e 's/^./    &/' \
			>> doc/help/$$cmd.rst; \
	done

dochtml: $(DOCBIN) cmd_help		## Build the docs HTML output.
	$(DOCBIN)/python doc/check_copied_from.py doc/*.rst
	$(SPHINXBUILD) -b html doc doc/_build/html

docdev: dochtml				## Build docs, and auto-watch for changes.
	PATH=$(DOCBIN):$(PATH) $(SPHINXAUTOBUILD) -b html doc doc/_build/html

docspell: $(DOCBIN)			## Run the spell checker on the docs.
	$(SPHINXBUILD) -b spelling doc doc/_spell

publish:
	rm -f $(WEBSAMPLE)/*.*
	mkdir -p $(WEBSAMPLE)
	cp doc/sample_html/*.* $(WEBSAMPLE)

publishbeta:
	rm -f $(WEBSAMPLEBETA)/*.*
	mkdir -p $(WEBSAMPLEBETA)
	cp doc/sample_html_beta/*.* $(WEBSAMPLEBETA)

CHANGES_MD = tmp/rst_rst/changes.md
RELNOTES_JSON = tmp/relnotes.json

$(CHANGES_MD): CHANGES.rst $(DOCBIN)
	$(SPHINXBUILD) -b rst doc tmp/rst_rst
	pandoc -frst -tmarkdown_strict --atx-headers --wrap=none tmp/rst_rst/changes.rst > $(CHANGES_MD)

relnotes_json: $(RELNOTES_JSON)		## Convert changelog to JSON for further parsing.
$(RELNOTES_JSON): $(CHANGES_MD)
	$(DOCBIN)/python ci/parse_relnotes.py tmp/rst_rst/changes.md $(RELNOTES_JSON)

github_releases: $(RELNOTES_JSON)	## Update GitHub releases.
	$(DOCBIN)/python ci/github_releases.py $(RELNOTES_JSON) nedbat/coveragepy
