#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GST_MEDIAMTX="${GST_MEDIAMTX:-$SCRIPT_DIR/gst/gst_mediamtx}"

UVC_VID="${UVC_VID:-0403}"
UVC_PID="${UVC_PID:-602a}"
UVC_RTSP_URL="${UVC_RTSP_URL:-rtsp://34.0.54.215:8554/mouthwatch}"
UVC_BPS="${UVC_BPS:-15000000}"
UVC_GOP="${UVC_GOP:-30}"

PID_THETA=""
PID_UVC=""

cleanup() {
    local sig="${1:-TERM}"
    trap - INT TERM EXIT
    if [[ -n "$PID_UVC" ]] && kill -0 "$PID_UVC" 2>/dev/null; then
        kill "-$sig" "$PID_UVC" 2>/dev/null || true
    fi
    if [[ -n "$PID_THETA" ]] && kill -0 "$PID_THETA" 2>/dev/null; then
        kill "-$sig" "$PID_THETA" 2>/dev/null || true
    fi
    wait 2>/dev/null || true
}

trap 'cleanup INT' INT
trap 'cleanup TERM' TERM
trap 'cleanup TERM' EXIT

find_uvc_device() {
    if [[ -n "${UVC_DEVICE:-}" ]]; then
        if [[ -e "$UVC_DEVICE" ]]; then
            echo "$UVC_DEVICE"
            return 0
        fi
        echo "Aviso: UVC_DEVICE='$UVC_DEVICE' no existe." >&2
        return 1
    fi

    local dev name vid pid cur idx
    for dev in /dev/video*; do
        [[ -e "$dev" ]] || continue
        name="$(basename "$dev")"
        vid=""
        pid=""

        if command -v udevadm >/dev/null 2>&1; then
            local props
            props="$(udevadm info --query=property --name="$dev" 2>/dev/null || true)"
            vid="$(awk -F= '/^ID_VENDOR_ID=/{print tolower($2); exit}' <<< "$props")"
            pid="$(awk -F= '/^ID_MODEL_ID=/{print tolower($2); exit}' <<< "$props")"
        fi

        if [[ -z "$vid" || -z "$pid" ]] && [[ -e "/sys/class/video4linux/$name/device" ]]; then
            cur="$(readlink -f "/sys/class/video4linux/$name/device")"
            while [[ "$cur" != "/" && -n "$cur" ]]; do
                if [[ -f "$cur/idVendor" && -f "$cur/idProduct" ]]; then
                    vid="$(tr '[:upper:]' '[:lower:]' < "$cur/idVendor")"
                    pid="$(tr '[:upper:]' '[:lower:]' < "$cur/idProduct")"
                    break
                fi
                cur="$(dirname "$cur")"
            done
        fi

        [[ "$vid" == "${UVC_VID,,}" && "$pid" == "${UVC_PID,,}" ]] || continue

        # Evitar nodos de metadata UVC: verificar que sea nodo de captura de video.
        if command -v v4l2-ctl >/dev/null 2>&1; then
            if v4l2-ctl --device="$dev" --list-formats 2>/dev/null | grep -qE '\[[0-9]+\]:'; then
                echo "$dev"
                return 0
            fi
        else
            idx="$(cat "/sys/class/video4linux/$name/index" 2>/dev/null || echo 0)"
            if [[ "$idx" == "0" ]]; then
                echo "$dev"
                return 0
            fi
        fi
    done

    return 1
}

# 1. Lanzar Ricoh Theta X (gst_mediamtx) de forma independiente
if [[ -x "$GST_MEDIAMTX" ]]; then
    echo "[stream_mediamtx] Iniciando gst_mediamtx (THETA -> rtsp://34.0.54.215:8554/theta)"
    # No redirigir stdout de gst_mediamtx: gst_viewer.c hace read(1, ...) en keywait().
    "$GST_MEDIAMTX" &
    PID_THETA=$!
else
    echo "[stream_mediamtx] Aviso: no se encontró ejecutable en $GST_MEDIAMTX. Se omite Ricoh Theta X." >&2
fi

# 2. Lanzar cámara intraoral UVC (0403:602a IOCplus+) de forma independiente
if ! command -v gst-launch-1.0 >/dev/null 2>&1; then
    echo "[stream_mediamtx] Aviso: gst-launch-1.0 no está instalado. Se omite cámara intraoral UVC." >&2
elif UVC_DEV="$(find_uvc_device)"; then
    echo "[stream_mediamtx] Iniciando UVC IOCplus+ ($UVC_DEV) -> H.265 -> $UVC_RTSP_URL"
    gst-launch-1.0 -e \
        v4l2src device="$UVC_DEV" ! \
        queue ! \
        videoconvert ! \
        video/x-raw,format=NV12 ! \
        queue ! \
        mpph265enc rc-mode=cbr bps="$UVC_BPS" gop="$UVC_GOP" ! \
        h265parse config-interval=-1 ! \
        queue ! \
        rtspclientsink location="$UVC_RTSP_URL" latency=0 protocols=tcp &
    PID_UVC=$!
else
    echo "[stream_mediamtx] Aviso: no se encontró dispositivo UVC ${UVC_VID}:${UVC_PID} (IOCplus+) en /dev/video*. Se omite cámara intraoral." >&2
fi

if [[ -z "$PID_THETA" && -z "$PID_UVC" ]]; then
    echo "[stream_mediamtx] Error: no se pudo iniciar ningún stream." >&2
    exit 1
fi

if [[ -n "$PID_THETA" ]]; then
    if ! wait "$PID_THETA"; then
        echo "[stream_mediamtx] Aviso: Ricoh Theta X no detectada o gst_mediamtx finalizó. El script continúa." >&2
    fi
fi

if [[ -n "$PID_UVC" ]]; then
    if ! wait "$PID_UVC"; then
        echo "[stream_mediamtx] Aviso: el pipeline de la cámara intraoral finalizó con error." >&2
    fi
fi
