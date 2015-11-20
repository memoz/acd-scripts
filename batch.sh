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

# 获取脚本路径
# Obtain script location
batch_path="${BASH_SOURCE%/*}"
if [[ ! -d "$batch_path" ]];
    then batch_path="$PWD";
fi

# 外部函数
# External functions
. "$batch_path/send_email.sh"
. "$batch_path/check_exit_code.sh"
. "$batch_path/clean_up.sh"

# 检查某些软件是否可用
# Check if some softwares are available
command -v mailx
check_exit_code $? "Check mailx"

# 获取待打包目录列表
# Obtain directory list
if [ -z "${1}" ]; then
    for file in *; do
        if [[ -d "${file}" && ! -L "${file}" ]]; then
            dir_list=("${dir_list[@]}" "${file}")
        fi
    done
else
    mapfile -t dir_list < "${1}"
    check_exit_code $? "Mapfile"
fi

# 向用户确认待打包目录
# Confirm directory list with user
echo -e "\n------------START OF DIRECTORY LIST------------\n"
printf '%s\n' "${dir_list[@]}"
echo -e "\n-------------END OF DIRECTORY LIST-------------\n"
echo "Proceed?"
select usr_choice in Yes No; do
    case "$usr_choice" in
        "Yes")
            echo "Proceed."
            break
            ;;
        "No")
            echo "User abort!"
            exit 1
            ;;
        *)
            echo "Invalid option."
    esac
done

# 分别处理每个目录
# Pack each directory
for dir in "${dir_list[@]}"; do
    printf "Start packing '$dir'...\n"
    "$batch_path/packer.sh" "$dir" auto-recover skip-db-check
    check_exit_code $? "packer.sh" "批量上传出错！"
done

# 完成，通知用户
# Done. Notify user.
send_email "批量上传完成。"
