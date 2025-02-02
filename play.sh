#!/bin/bash
uv run ansible-playbook -i inventory.ini site.yaml --tags all --ask-vault-pass
