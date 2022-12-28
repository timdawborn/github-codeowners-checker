.PHONY: install_deps lint run

.venv:
	-python3 -m venv .venv
	-make install_deps

install_deps: .venv
	-./.venv/bin/python -m pip install -U pip
	-./.venv/bin/python -m pip install -r requirements.development.txt

lint: .venv
	-./.venv/bin/python -m flake8 github-codeowners-checker.py
	-./.venv/bin/python -m mypy github-codeowners-checker.py
