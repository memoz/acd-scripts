#!/bin/bash
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


# 发送通知邮件
# Send notification emails
function send_email {
    echo "$1" | mailx \
    -s "Subject" \
    -S smtp="smtp.gmail.com:587" \
    -S smtp-use-starttls \
    -S smtp-auth=login \
    -S smtp-auth-user="user" \
    -S smtp-auth-password="password" \
    -S ssl-verify=ignore \
    user@example.com
}

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

# 数据库查询
# Database access
function db_query {
    n=0; i=0; IFS=$'\n'
    start=$(date --rfc-3339=seconds)
    printf "Start executing %s query at %s.\n" "$1" "$start"
    while true; do
        record=($(psql -Aqt -F$'\n' -c "$2" -d 'service=dsn1'))
        if [ $? -eq 0 ]; then
            finish=$(date --rfc-3339=seconds)
            printf "DB query finished at %s.\n" "$finish"
            IFS=$' \t\n'
            break
        fi
        for secs in $(seq 59 -1 0); do
            printf "\rDB query failed. Retrying in %02d..." "$secs"
            sleep 1
        done
        if [[ $((++n)) -eq 10 ]]; then
            send_email "General DB query failed after 10 tries. Still trying..."
            n=0
        fi
    done
}

# 响应Unix信号
# Respond to Unix signals
function clean_up {
	printf "\nSignal caught, abort.\n"
	exit 1
}
trap clean_up SIGHUP SIGINT SIGTERM

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
command -v psql
check_exit_code $? "Check psql"

# 检查输入参数
# Check input arguments
if [ -z "$1" ]; then
    echo "A target directory is required."
	exit 1
fi

# 转存输入参数
# Copy input arguments
bash_args=("$@")

# 定义全局变量
# Define global variables
prior_steps=0
record=()
tree_saved=0
record_exist=0
q1="SELECT arc_no, password, status FROM summary WHERE arc_no = (SELECT name FROM dir_tree WHERE node_id = (SELECT parent_id FROM dir_tree WHERE name = '${bash_args[0]}'))::BIGINT"
q2="SELECT arc_no, password, status FROM summary WHERE descr = '${bash_args[0]}'"

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
        arc_no=${record[0]}
        a_pwd=${record[1]}
    else
        # 生成新编号和密码
        # Generate new number and password
        arc_no=$(date +%s)
        a_pwd=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 43 | head -n 1)
    fi

    # 创建工作目录
    # Create working directories
    mkdir -p ~/$arc_no
    check_exit_code $? "mkdir" "创建新目录失败！"
    mkdir -p ~/xml_trees
    check_exit_code $? "mkdir" "创建新目录失败！"

    # 保存待打包目录的结构
    # Save directory structure
    tree --du -saX "${bash_args[0]}" > ~/xml_trees/$arc_no.xml
    check_exit_code $? "tree" "保存目录结构失败！"
    read act_size dirs files <<< $(xmlstarlet sel -t -v /tree/report/size -n -v /tree/report/directories -n -v /tree/report/files -n ~/xml_trees/$arc_no.xml)
    check_exit_code $? "read" "读取xml失败！"

    # 存入数据库
    # Create new records in the database
    if [ $record_exist -eq 0 ]; then
        db_query "initial INSERT" "INSERT INTO summary (arc_no, act_size, dirs, files, status, password, descr) VALUES ('$arc_no', '$act_size', '$dirs', '$files', 'packing', '$a_pwd', '${bash_args[0]}')"
    fi
    c_dir="$(pwd)"
    if [ $tree_saved -eq 0 ]; then
        cd ~/xml_trees/
        until ~/savetree.py $arc_no; do
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
    rm $arc_no.xml

    # 返回打包起始目录
    # Return to starting directory
    cd "$c_dir"
    check_exit_code $? "cd into "$c_dir "返回起始目录失败！"

    # 删除残留的压缩包
    # Delete left-overs
    rm ~/$arc_no/$arc_no.7z.*

    # 打包
    # Pack
    7z a -t7z -v500m -m0=lzma2 -mx=9 -mmt=on -mhe=on -p$a_pwd ~/$arc_no/$arc_no.7z "${bash_args[0]}"
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
        arc_no=${record[0]}
        a_pwd=${record[1]}
    fi

    # 进入存档目录
    # Switch to archive directory
    cd ~/$arc_no/
    check_exit_code $? "cd into "$arc_no "进入存档目录失败！"

    # 计算分卷数和总大小
    # Calculate total volume and total size
    read aprnt_size vols <<< $(ls -l *.7z.* | awk '{s+=$5} END {printf "%.0f "NR, s}')

    # 更新数据库
    # Update database
    db_query "1st UPDATE" "UPDATE summary SET vols='$vols', aprnt_size='$aprnt_size', status='testing' WHERE arc_no='$arc_no'"

    # 测试
    # Test
    7z t $arc_no.7z.001 -p$a_pwd
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
        arc_no=${record[0]}
        # 进入存档目录 Switch to archive directory
        cd ~/$arc_no/
        check_exit_code $? "cd into "$arc_no "进入存档目录失败！"
    fi

    # 更新数据库
    # Update database
    db_query "2nd UPDATE" "UPDATE summary SET status='generating par2' WHERE arc_no='$arc_no'"

    # 删除残留的par2
    # Delete previous pars
    rm $arc_no.7z.par2 $arc_no.7z.vol*

    # 生成par2
    # Generate par2
    par2 c -s4096000 -r5 -l $arc_no.7z *
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
        arc_no=${record[0]}
    fi

    # 更新数据库
    # Update database
    db_query "3rd UPDATE" "UPDATE summary SET status='uploading' WHERE arc_no='$arc_no'"

    # 上传至ACD
    # Upload to ACD
    cd ~
    acdcli sync && acdcli ul $arc_no /Archives
    acdcli sync && acdcli ul $arc_no /Archives
    check_exit_code $? "acdcli" "上传失败！"

    # 删除压缩包
    # Delete local archives
    rm -r $arc_no

    # 更新数据库
    # Update database
    db_query "final UPDATE" "UPDATE summary SET status='done' WHERE arc_no='$arc_no'"

    # 完成，通知用户
    # Done. Notify user
    printf "All done!\n"
    send_email "打包上传成功！"

fi
