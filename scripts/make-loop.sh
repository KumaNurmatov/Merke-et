#!/usr/bin/env bash
# Готовит ролик для фонового автоплея: без звука, H.264, до 1600 px по ширине,
# moov в начале файла (играет без полной загрузки) и бесшовная петля.
#
# Петля: камера за ролик успевает немного отъехать, поэтому стык «конец → начало»
# заметен. Выбрасываем первые XF секунд, а хвост растворяем в них — последний
# кадр совпадает с первым.
#
#   scripts/make-loop.sh исходник.mp4 assets/video/hero-bull.mp4 [crf] [xf]
set -euo pipefail

src=${1:?нужен исходный файл}
out=${2:?нужен файл назначения}
crf=${3:-24}
xf=${4:-0.45}

ffmpeg=$(command -v ffmpeg || python3 -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')
# ffmpeg без выходного файла завершается кодом 1 — при pipefail это убило бы скрипт
dur=$({ "$ffmpeg" -nostdin -i "$src" 2>&1 || true; } \
  | sed -n 's/.*Duration: \([0-9]*\):\([0-9]*\):\([0-9.]*\).*/\1 \2 \3/p' \
  | awk '{printf "%.3f", $1*3600 + $2*60 + $3}')
main=$(awk -v d="$dur" -v x="$xf" 'BEGIN{printf "%.3f", d-x}')
echo "длительность $dur с, растворяем последние $xf с в начале"

"$ffmpeg" -nostdin -y -loglevel error -i "$src" -an \
  -filter_complex "[0:v]scale='min(1600,iw)':-2,setsar=1,split=3[v0][v1][v2];[v0]trim=start=$xf:end=$main,setpts=PTS-STARTPTS[body];[v1]trim=start=$main,setpts=PTS-STARTPTS[tail];[v2]trim=start=0:end=$xf,setpts=PTS-STARTPTS[head];[tail][head]blend=all_expr='A*(1-(T/$xf))+B*(T/$xf)'[mix];[body][mix]concat=n=2:v=1:a=0[out]" \
  -map "[out]" \
  -c:v libx264 -profile:v high -pix_fmt yuv420p \
  -crf "$crf" -preset slow -movflags +faststart \
  "$out"

ls -la "$out"
