#!/bin/sh
# ZED -> Telegram: solo eventos relevantes, con límite de frecuencia por clase
. "${ZED_ZEDLET_DIR}/zed.rc"
. "${ZED_ZEDLET_DIR}/zed-functions.sh"
case "${ZEVENT_SUBCLASS}" in
  statechange)
    [ "${ZEVENT_VDEV_STATE_STR}" = "ONLINE" ] && exit 0
    msg="⚠️ ZFS ${ZEVENT_POOL}: ${ZEVENT_VDEV_PATH:-vdev} pasó a ${ZEVENT_VDEV_STATE_STR}" ;;
  io|checksum|data|deadman)
    msg="⚠️ ZFS ${ZEVENT_POOL}: error ${ZEVENT_SUBCLASS} en ${ZEVENT_VDEV_PATH:-?}" ;;
  scrub_finish|resilver_finish)
    msg="🧹 ZFS ${ZEVENT_POOL}: ${ZEVENT_SUBCLASS} — $(zpool status -x "${ZEVENT_POOL}" | head -1)" ;;
  *) exit 0 ;;
esac
zed_rate_limit "${ZEVENT_POOL};${ZEVENT_SUBCLASS};telegram" || exit 0
notify-telegram "$msg"
