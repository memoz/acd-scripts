#!/usr/bin/python3
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

import argparse, psycopg2, time, sys
from lxml import etree
from collections import defaultdict
from datetime import datetime, timezone, timedelta

# 接受命令行参数
# Accept arguments
parser = argparse.ArgumentParser(description="Save specified archive tree in the current directory to database.")
parser.add_argument("arc_no", type=int, help="Archive number.")
args = parser.parse_args()

# 开始执行的时刻
# Take start time
start_time = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0).isoformat(' ')
sys.stdout.write(start_time+' Start saving directory tree...\n')

# 连接至数据库
# Connect to database
while True:
    try:
        conn = psycopg2.connect('service=dsn1')
    except Exception as e:
        for i in range(30, 0, -1):
            text = '\r{}! Retrying in {:02d}'.format(e, i).replace('\n', '')
            sys.stdout.write(text)
            time.sleep(1)
        continue
    break
cur = conn.cursor()

# 定义共用查询语句
# Common queries
dir = "INSERT INTO dir_tree (name, size, is_dir, parent_id) VALUES (%s, %s, True, %s) RETURNING node_id;"
file = "INSERT INTO dir_tree (name, size, parent_id) VALUES (%s, %s, %s);"

# 自动激活的任意深度字典
# Dictionary with autovivification
def rec_dd():
    return defaultdict(rec_dd)

# 插入根节点
# Insert the root node
node_ref = rec_dd()
cur.execute("INSERT INTO dir_tree (name, is_dir) VALUES (%s, True) RETURNING node_id;", [args.arc_no])
node_ref[0][None] = cur.fetchone()[0]

# 遍历整个目录树
# Iterate through the whole tree
tree = etree.parse(str(args.arc_no)+".xml")
root = tree.find("directory")
for element in root.iter():
    name = element.get("name")
    size = element.get("size")
    path = tree.getelementpath(element)
    depth = path.count("/")+1
    pname = element.getparent().get("name")
    pnode = node_ref[depth-1][pname]
    #print("%s %s D%s %s - D%s %s" % (element.tag, size, depth, name, depth-1, pname))
    if element.tag == 'directory':
        cur.execute(dir, [name, size, pnode])
        node_ref[depth][name] = cur.fetchone()[0]
    else:
        cur.execute(file, [name, size, pnode])

# 保存更改，关闭连接
# Commit changes and close connection
conn.commit()
finish_time = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0).isoformat(' ')
sys.stdout.write(finish_time+' Directory tree saved.\n')
cur.close()
conn.close()
