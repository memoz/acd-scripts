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

function echo_usage {
    echo "Usage: ${BASH_SOURCE[0]}  (<A directory name>)  [skip-db-check | auto-recover | continue-from-pack |"
    echo "                     continue-from-test | continue-from-par2 | continue-from-upload]  [skip-db-check]"
}

# 检查输入参数 1
# Check input argument 1
if [ -z "$1" ]; then
    echo "A directory name is required!"
    echo_usage
    exit 1
elif [ -d "$1" ]; then
    if [ -L "$1" ]; then
        echo "Symlinks are not supported!"
        echo_usage
        exit 1
    fi
else
    echo "'$1' is not a directory or does not exist!"
    echo_usage
    exit 1
fi

# 检查输入参数 2
# Check input argument 2
if [ -n "$2" ] && [ "$2" != "skip-db-check" ] && [ "$2" != "auto-recover" ] && [ "$2" != "continue-from-pack" ] && \
   [ "$2" != "continue-from-test" ] && [ "$2" != "continue-from-par2" ] && [ "$2" != "continue-from-upload" ]; then
    echo "Argument 2 not understood!"
    echo_usage
    exit 1
fi

# 检查输入参数 3
# Check input argument 3
if [ -n "$3" ] && [ "$3" != "skip-db-check" ]; then
    echo "Argument 3 not understood!"
    echo_usage
    exit 1
fi

# 复制输入参数
# Copy input arguments
bash_args=("$@")

# 获取脚本路径
# Obtain script location
packer_path="${BASH_SOURCE%/*}"
if [[ ! -d "$packer_path" ]];
    then packer_path="$PWD";
fi

# 加载外部函数
# Load external functions
. "$packer_path/send_email.sh"
. "$packer_path/check_exit_code.sh"
. "$packer_path/db_query.sh"
. "$packer_path/clean_up.sh"

# 检查某些软件是否可用
# Check availability of some softwares
command -v tree
check_exit_code $? "Check tree"
command -v 7z
check_exit_code $? "Check 7z"
command -v par2
check_exit_code $? "Check par2"
command -v mailx
check_exit_code $? "Check mailx"
command -v xmlstarlet
check_exit_code $? "Check xmlstarlet"
command -v tidy
check_exit_code $? "Check tidy"
command -v psql
check_exit_code $? "Check psql"

# 定义全局变量
# Define global variables
prior_steps=0
record=()
tree_saved=0
record_exist=0
q1="SELECT arc_no, password, status FROM summary WHERE arc_no = (SELECT name FROM dir_tree WHERE node_id = (SELECT parent_id FROM dir_tree WHERE name = '${bash_args[0]//\'/\'\'}'))::BIGINT"
q2="SELECT arc_no, password, status FROM summary WHERE descr = '${bash_args[0]//\'/\'\'}'"
work_path="$HOME"

# 检查数据库是否可用
# Check database connection
if [ "${bash_args[1]}" != "skip-db-check" ] && [ "${bash_args[2]}" != "skip-db-check" ]; then
    echo "Checking database availability..."
    psql -c '\q' -d 'service=dsn1'
    check_exit_code $? "psql"
fi

# 自动判断进度并恢复
# Automatic progress detection and recovery
if [ "${bash_args[1]}" == "auto-recover" ]; then
    printf "Looking up previous progress...\n"
    db_query "SELECT" "$q1"
    tree_saved=1
    if [ -z "${record[2]}" ]; then
        db_query "SELECT" "$q2"
        tree_saved=0
    fi
    case "${record[2]}" in
        'packing')
            bash_args[1]='continue-from-pack'
            ;;
        'testing')
            bash_args[1]='continue-from-test'
            ;;
        'generating par2')
            bash_args[1]='continue-from-par2'
            ;;
        'uploading')
            bash_args[1]='continue-from-upload'
            ;;
        'done')
            printf "Already uploaded. All done.\n"
            exit 0
            ;;
        *)
            bash_args[1]=''
            printf "Fresh start.\n"
            ;;
    esac
fi


######################## 打包 Pack ########################
if [ -z "${bash_args[1]}" ] || [ "${bash_args[1]}" == "skip-db-check" ] || [ "${bash_args[1]}" == "continue-from-pack" ]; then
    if [ "${bash_args[1]}" == "continue-from-pack" ]; then
        printf "Continuing from pack.\n"
        record_exist=1
        # 如已获取记录则继续，否则依次尝试查询1和查询2，仍失败则报错。
        # Continue if record already obtained, or try query1 then query2. Raise error if all fail.
        if [ -z "${record[0]}" ] || [ -z "${record[1]}" ]; then
            db_query "SELECT" "$q1"
            tree_saved=1
            if [ -z "${record[0]}" ] || [ -z "${record[1]}" ]; then
                db_query "SELECT" "$q2"
                tree_saved=0
                if [ -z "${record[0]}" ] || [ -z "${record[1]}" ]; then
                    printf "Unable to obtain previous record, abort!"
                    exit 1
                fi
            fi
        fi
        arc_no="${record[0]}"
        a_pwd="${record[1]}"
    else
        # 生成新编号和密码
        # Generate new number and password
        arc_no="$(date +%s)"
        a_pwd="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 43 | head -n 1)"
    fi

    # 创建工作目录
    # Create working directories
    mkdir -p "$work_path/$arc_no"
    check_exit_code $? "mkdir" "创建新目录失败！"
    mkdir -p "$work_path/xml_trees"
    check_exit_code $? "mkdir" "创建新目录失败！"

    # 保存待打包目录的结构
    # Save directory structure
    tree --du -saX "${bash_args[0]}" > "$work_path/xml_trees/$arc_no.xml"
    check_exit_code $? "tree" "保存目录结构失败！"
    tidy -miq -xml -utf8 -f "$work_path/xml_trees/tidy_$arc_no.log" "$work_path/xml_trees/$arc_no.xml"
    if [ $? -gt 1 ]; then
        echo "Unable to fix invalid xml!"
        send_email "$work_path/xml_trees/tidy_$arc_no.log"
        exit 1
    fi
    s_d_f=($(xmlstarlet sel -t -v /tree/report/size -o ' ' -v /tree/report/directories -o ' ' -v /tree/report/files "$work_path/xml_trees/$arc_no.xml"))
    check_exit_code $? "xmlstarlet" "读取xml失败！"

    # 存入数据库
    # Create new records in the database
    if [ $record_exist -eq 0 ]; then
        db_query "initial INSERT" "INSERT INTO summary (arc_no, act_size, dirs, files, status, password, descr) VALUES ('$arc_no', '${s_d_f[0]}', '${s_d_f[1]}', '${s_d_f[2]}', 'packing', '$a_pwd', '${bash_args[0]//\'/\'\'}')"
    fi
    c_dir="$(pwd)"
    if [ $tree_saved -eq 0 ]; then
        cd "$work_path/xml_trees/"
        until "$packer_path/savetree.py" "$arc_no"; do
            for secs in $(seq 59 -1 0); do
                printf "\rSaving directory tree failed. Retrying in %02d..." "$secs"
                sleep 1
            done
            if [ $((++failures)) -eq 5 ]; then
                send_email "Saving directory tree failed for 5 times. Still retrying..."
            fi
        done
    fi

    # 删除临时文件
    # Delete temporary files
    rm -f "$work_path/xml_trees/$arc_no.xml"
    check_exit_code $? "rm" "删除文件失败！"

    # 返回打包起始目录
    # Return to starting directory
    cd "$c_dir"
    check_exit_code $? "cd into $c_dir" "返回起始目录失败！"

    # 删除残留的压缩包
    # Delete left-overs
    rm -f "$work_path/$arc_no/$arc_no.7z.*"
    check_exit_code $? "rm" "删除文件失败！"

    # 打包
    # Pack
    7z a -t7z -mx=0 -ms=off -mhe=on -m0=copy -v500m -p"$a_pwd" "$work_path/$arc_no/$arc_no.7z" "${bash_args[0]}"
    check_exit_code $? "7z add" "打包失败！"

    # 设置步骤标志
    # Set flag
    ((prior_steps++))

fi


######################## 测试 Test ########################
if [ "$prior_steps" -gt 0 ] || [ "${bash_args[1]}" == "continue-from-test" ]; then
    if [ "${bash_args[1]}" == "continue-from-test" ]; then
        printf "Continuing from test.\n"
        if [ -z "${record[0]}" ] || [ -z "${record[1]}" ]; then
            db_query "SELECT" "$q1"
        fi
        arc_no="${record[0]}"
        a_pwd="${record[1]}"
    fi

    # 进入存档目录
    # Switch to archive directory
    cd "$work_path/$arc_no/"
    check_exit_code $? "cd into $arc_no" "进入存档目录失败！"

    # 计算分卷数和总大小
    # Calculate total volume and total size
    read aprnt_size vols <<< $(ls -l *.7z.* | awk '{s+=$5} END {printf "%.0f "NR, s}')

    # 更新数据库
    # Update database
    db_query "1st UPDATE" "UPDATE summary SET vols='$vols', aprnt_size='$aprnt_size', status='testing' WHERE arc_no='$arc_no'"

    # 测试
    # Test
    7z t "$arc_no.7z.001" -p"$a_pwd"
    check_exit_code $? "7z test" "测试失败！"

    # 设置步骤标志
    # Set flag
    ((prior_steps++))

fi


############# 生成修复文件 Generate recovery files #############
if [ "$prior_steps" -gt 0 ] || [ "${bash_args[1]}" == "continue-from-par2" ]; then
    if [ "${bash_args[1]}" == "continue-from-par2" ]; then
        printf "Continuing from par2.\n"
        if [ -z "${record[0]}" ]; then
            db_query "SELECT" "$q1"
        fi
        arc_no="${record[0]}"
        # 进入存档目录
        # Switch to archive directory
        cd "$work_path/$arc_no/"
        check_exit_code $? "cd into $arc_no" "进入存档目录失败！"
    fi

    # 更新数据库
    # Update database
    db_query "2nd UPDATE" "UPDATE summary SET status='generating par2' WHERE arc_no='$arc_no'"

    # 删除残留的par2
    # Delete previous pars
    rm -f "$arc_no.7z.par2" "$arc_no.7z.vol*"
    check_exit_code $? "rm" "删除文件失败！"

    # 生成par2
    # Generate par2
    par2 c -s16777216 -r5 -l "$arc_no.7z" *
    check_exit_code $? "par2" "生成修复文件失败！"

    # 设置步骤标志
    # Set flag
    ((prior_steps++))

fi


######################## 上传 Upload ########################
if [ "$prior_steps" -gt 0 ] || [ "${bash_args[1]}" == "continue-from-upload" ]; then
    if [ "${bash_args[1]}" == "continue-from-upload" ]; then
        printf "Continuing from upload.\n"
        if [ -z "${record[0]}" ]; then
            db_query "SELECT" "$q1"
        fi
        arc_no="${record[0]}"
    fi

    # 更新数据库
    # Update database
    db_query "3rd UPDATE" "UPDATE summary SET status='uploading' WHERE arc_no='$arc_no'"

    # 上传至ACD
    # Upload to ACD
    failures=0
    until acdcli sync && acdcli ul -x 2 "$work_path/$arc_no" /Archives; do
        for secs in $(seq 89 -1 0); do
            printf "\rUploading failed. Retrying in %02d..." "$secs"
            sleep 1
        done
        if [ $((++failures)) -eq 5 ]; then
            send_email "Uploading failed for 5 times. Still retrying..."
        fi
    done

    # 删除压缩包
    # Delete local archives
    cd "$work_path"
    rm -rf "$work_path/$arc_no"
    check_exit_code $? "rm" "删除文件失败！"

    # 更新数据库
    # Update database
    db_query "final UPDATE" "UPDATE summary SET status='done' WHERE arc_no='$arc_no'"

    # 完成，通知用户
    # Done. Notify user
    printf "All done!\n"
    send_email "打包上传成功！"

fi
