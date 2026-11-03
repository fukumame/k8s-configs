#!/bin/bash
# Usage: ./play.sh <env> --tags <tags> [other ansible-playbook options]
#   <env> is a directory under inventories/ (see inventories/example/).
#   A protected environment also needs "-e confirm_env=<env>".
set -eu
cd "$(dirname "$0")"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <env> --tags <tags> [ansible-playbook options]" >&2
  echo "Environments: $(ls inventories | tr '\n' ' ')" >&2
  exit 1
fi

inventory="inventories/$1/hosts.ini"
shift
if [ ! -f "$inventory" ]; then
  echo "Inventory not found: $inventory" >&2
  exit 1
fi

case " $* " in
  *" --tags "* | *" --tags="* | *" -t "*) ;;
  *)
    echo "Specify --tags (for a new cluster: --tags all)." >&2
    exit 1
    ;;
esac

exec uv run ansible-playbook -i "$inventory" site.yaml --ask-vault-pass "$@"
