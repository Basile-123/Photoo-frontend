#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/deploy-to-photobooth.sh deploy
  scripts/deploy-to-photobooth.sh restore BACKUP_DIR

Environment:
  BUILD_DIR              Build directory to deploy. Default: ./dist/spa, then ../photobooth-app/src/web/frontend.
  PHOTOBOOTH_PYTHON      Python executable from the photobooth-app pipx venv.
  PHOTOBOOTH_FRONTEND_DIR Frontend directory served by photobooth-app.
  BACKUP_ROOT            Backup root. Default: ./deploy-backups.

The script never edits config.json, media files, databases, userdata, camera settings, or QR settings.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:-}"
backup_arg="${2:-}"

if [[ -z "$action" ]]; then
  usage
  exit 2
fi

python_bin="${PHOTOBOOTH_PYTHON:-$HOME/.local/share/pipx/venvs/photobooth-app/bin/python}"
backup_root="${BACKUP_ROOT:-$repo_root/deploy-backups}"

detect_frontend_dir() {
  if [[ -n "${PHOTOBOOTH_FRONTEND_DIR:-}" ]]; then
    printf '%s\n' "$PHOTOBOOTH_FRONTEND_DIR"
    return
  fi

  "$python_bin" -c 'import importlib.util, pathlib
spec = importlib.util.find_spec("photobooth")
if spec is None or spec.origin is None:
    raise SystemExit("photobooth package not found")
print(pathlib.Path(spec.origin).parents[1] / "web" / "frontend")'
}

detect_build_dir() {
  if [[ -n "${BUILD_DIR:-}" ]]; then
    printf '%s\n' "$BUILD_DIR"
  elif [[ -f "$repo_root/dist/spa/index.html" ]]; then
    printf '%s\n' "$repo_root/dist/spa"
  else
    printf '%s\n' "$repo_root/../photobooth-app/src/web/frontend"
  fi
}

assert_photobooth_stopped() {
  if systemctl --user is-active --quiet photobooth-app; then
    echo "ERROR: photobooth-app is still active. Stop it before deploying." >&2
    exit 1
  fi
}

assert_frontend_dir() {
  local dir="$1"
  if [[ ! -d "$dir" || ! -f "$dir/index.html" || ! -d "$dir/assets" ]]; then
    echo "ERROR: frontend directory is not valid: $dir" >&2
    exit 1
  fi
}

assert_build_dir() {
  local dir="$1"
  if [[ ! -d "$dir" || ! -f "$dir/index.html" || ! -d "$dir/assets" ]]; then
    echo "ERROR: build directory is not valid: $dir" >&2
    exit 1
  fi
}

copy_frontend() {
  local source_dir="$1"
  local target_dir="$2"
  rsync -a --delete --itemize-changes "$source_dir"/ "$target_dir"/
}

case "$action" in
  deploy)
    frontend_dir="$(detect_frontend_dir)"
    build_dir="$(detect_build_dir)"
    assert_photobooth_stopped
    assert_frontend_dir "$frontend_dir"
    assert_build_dir "$build_dir"

    timestamp="$(date -u +%Y%m%d-%H%M%S)"
    backup_dir="$backup_root/frontend-$timestamp"
    mkdir -p "$backup_dir"

    echo "Backing up current frontend:"
    echo "  from: $frontend_dir"
    echo "  to:   $backup_dir"
    copy_frontend "$frontend_dir" "$backup_dir"

    echo "Deploying new frontend:"
    echo "  from: $build_dir"
    echo "  to:   $frontend_dir"
    copy_frontend "$build_dir" "$frontend_dir"

    echo "Deployment complete."
    echo "Restore command:"
    echo "  $0 restore '$backup_dir'"
    ;;
  restore)
    if [[ -z "$backup_arg" ]]; then
      echo "ERROR: restore requires BACKUP_DIR." >&2
      usage
      exit 2
    fi

    frontend_dir="$(detect_frontend_dir)"
    assert_photobooth_stopped
    assert_frontend_dir "$frontend_dir"
    assert_build_dir "$backup_arg"

    echo "Restoring frontend:"
    echo "  from: $backup_arg"
    echo "  to:   $frontend_dir"
    copy_frontend "$backup_arg" "$frontend_dir"
    echo "Restore complete."
    ;;
  *)
    usage
    exit 2
    ;;
esac
