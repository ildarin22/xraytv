#!/bin/sh
# Хук webosbrew init.d: отложенный запуск Xray. Симлинк на него создаёт «xrayctl setup».
exec sh /media/developer/apps/usr/palm/applications/xraytv.app/xrayctl boot
