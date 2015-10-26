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

# 错误处理
# Error handling
function check_exit_code {
    if [[ $1 -ne 0 ]]; then
        echo $2" command FAILED with exit code: "$1
            if [[ -n $3 ]]; then
                send_email "$3"
            fi
        exit 1
    fi
}
