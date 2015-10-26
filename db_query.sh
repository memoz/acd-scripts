#!/usr/bin/env bash
#
# Copyright (C) 2015  Bowen Jiang  (unctas@gmail.com)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# 数据库查询
# Database access
function db_query {
    n=0; i=0; IFS=$'\n'
    start=$(date --rfc-3339=seconds)
    printf "%s Executing %s query...\n" "$start" "$1"
    while true; do
        record=($(psql -Aqt -F$'\n' -c "$2" -d 'service=dsn1'))
        if [ $? -eq 0 ]; then
            finish=$(date --rfc-3339=seconds)
            printf "%s DB query succeeded.\n" "$finish"
            IFS=$' \t\n'
            break
        fi
        for secs in $(seq 59 -1 0); do
            printf "\rDB query failed! Retrying in %02d..." "$secs"
            sleep 1
        done
        printf "\n"
        if [[ $((++n)) -eq 10 ]]; then
            send_email "General DB query failure after 10 tries. Still trying..."
        fi
    done
}

