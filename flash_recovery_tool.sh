#!/usr/bin/env bash
set -euo pipefail

# Ferramenta simples para flash via fastboot e entrada imediata no recovery.
# Uso típico:
#   ./flash_recovery_tool.sh --recovery twrp.img
#   ./flash_recovery_tool.sh --boot patched_boot.img
#   ./flash_recovery_tool.sh --recovery twrp.img --slot b

print_help() {
  cat <<'HELP'
Flash Recovery Tool (ADB/Fastboot)

Uso:
  ./flash_recovery_tool.sh [opções]

Opções:
  --recovery <arquivo.img>   Faz flash da partição recovery
  --boot <arquivo.img>       Faz flash da partição boot (ex.: patched_boot.img para root)
  --vbmeta <arquivo.img>     Faz flash da partição vbmeta (opcional)
  --slot <a|b>               Força slot ativo (aparelhos A/B)
  --dry-run                  Mostra comandos sem executar
  -h, --help                 Mostra esta ajuda

Fluxo:
  1) Reinicia para bootloader (se necessário)
  2) Faz o flash das imagens informadas
  3) Reinicia DIRETO para recovery sem usar botões físicos

Pré-requisitos:
  - adb e fastboot instalados
  - Bootloader desbloqueado
  - Depuração USB autorizada (quando em Android)
HELP
}

err() {
  echo "[ERRO] $*" >&2
}

log() {
  echo "[INFO] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Comando '$1' não encontrado no PATH."
    exit 1
  }
}

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY-RUN] $*"
  else
    "$@"
  fi
}

wait_fastboot() {
  local timeout="${1:-30}"
  local elapsed=0

  while true; do
    if fastboot devices | awk '{print $1}' | grep -q .; then
      return 0
    fi

    if (( elapsed >= timeout )); then
      return 1
    fi

    sleep 1
    ((elapsed++))
  done
}

RECOVERY_IMG=""
BOOT_IMG=""
VBMETA_IMG=""
SLOT=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recovery)
      RECOVERY_IMG="${2:-}"
      shift 2
      ;;
    --boot)
      BOOT_IMG="${2:-}"
      shift 2
      ;;
    --vbmeta)
      VBMETA_IMG="${2:-}"
      shift 2
      ;;
    --slot)
      SLOT="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      err "Opção desconhecida: $1"
      print_help
      exit 1
      ;;
  esac
done

if [[ -z "$RECOVERY_IMG" && -z "$BOOT_IMG" && -z "$VBMETA_IMG" ]]; then
  err "Informe pelo menos uma imagem para flash (--recovery, --boot ou --vbmeta)."
  exit 1
fi

for f in "$RECOVERY_IMG" "$BOOT_IMG" "$VBMETA_IMG"; do
  if [[ -n "$f" && ! -f "$f" ]]; then
    err "Arquivo não encontrado: $f"
    exit 1
  fi
done

if [[ -n "$SLOT" && "$SLOT" != "a" && "$SLOT" != "b" ]]; then
  err "Slot inválido. Use --slot a ou --slot b"
  exit 1
fi

require_cmd adb
require_cmd fastboot

log "Checando dispositivo conectado via ADB..."
if adb get-state >/dev/null 2>&1; then
  log "Dispositivo detectado em modo Android. Reiniciando para bootloader..."
  run_cmd adb reboot bootloader
else
  log "ADB indisponível agora. Tentando continuar assumindo que já está em fastboot..."
fi

log "Aguardando modo fastboot..."
if ! wait_fastboot 40; then
  err "Nenhum dispositivo fastboot detectado. Verifique cabo/driver/USB."
  exit 1
fi

if [[ -n "$SLOT" ]]; then
  log "Definindo slot ativo: $SLOT"
  run_cmd fastboot --set-active="$SLOT"
fi

if [[ -n "$VBMETA_IMG" ]]; then
  log "Flash vbmeta: $VBMETA_IMG"
  run_cmd fastboot flash vbmeta "$VBMETA_IMG"
fi

if [[ -n "$BOOT_IMG" ]]; then
  log "Flash boot: $BOOT_IMG"
  run_cmd fastboot flash boot "$BOOT_IMG"
fi

if [[ -n "$RECOVERY_IMG" ]]; then
  log "Flash recovery: $RECOVERY_IMG"
  run_cmd fastboot flash recovery "$RECOVERY_IMG"
fi

log "Entrando diretamente no recovery..."
run_cmd fastboot reboot recovery

log "Concluído."
