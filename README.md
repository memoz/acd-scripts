# acd-scripts
Amazon Cloud Drive (ACD) 是 Amazon 提供的一项个人网络硬盘服务。本项目将一些Shell下的软件结合起来，自动对大体积文件夹打包上传。
Looking for [English README](README_EN.md)?

# 整体功能
- 对单个文件夹自动完成分卷压缩、加密、测试、添加修复文件和上传，并保存目录结构和密码等到PostgreSQL数据库。
- 某些步骤出错和完成时可发送电子邮件通知用户。
- 可选择自动判断或手动指定从哪一步开始，便于中断后继续。

# 文件说明
    脚本    |  运行环境  |   功能
----------- | ---------- | ---------
packer.sh   | GNU Bash   | 主程序
savetree.py | Python 3   | 将xml目录树转换成邻接表
db-init.sql | PostgreSQL | 创建索引数据库

# 依赖关系
除了必备的GNU Core Utils之外还需要：

      软件     |    用途
-------------- | ------------
tree           | 列出目录树
p7zip          | 压缩和加密
par2           | 生成修复文件
heirloom-mailx | 发送电子邮件
xmlstarlet     | 解析xml文件
psql           | 访问数据库
acd_cli        | 上传至ACD
[acd_cli](https://github.com/yadayada/acd_cli)为另一Github项目，其余为自由软件。

# 用法
以Debian Jessie为例，其它发行版请使用相应的包管理器。配置文件位置可能不同。
## 初次使用
### 生成自签署的数字证书
用于代替密码访问数据库。
#### 根证书
```
openssl genrsa -out rootCA.key 2048
openssl req -x509 -new -nodes -key rootCA.key -days 1024 -out rootCA.pem
```
#### 签发服务器及客户端证书
将device改为对应的名字，如client、server。对于"Common Name(FQDN)"字段，客户端证书请填写用户名，服务器证书请填写客户端连接用的服务器IP地址或域名。
```
openssl genrsa -out device.key 2048
openssl req -new -key device.key -out device.csr
openssl x509 -req -in device.csr -CA root.pem -CAkey rootCA.key -CAcreateserial -out device.crt -days 500
```
### 设置数据库服务器
#### 安装PostgreSQL
```
sudo aptitude install postgresql
```

#### 切换至用户postgres
```
sudo su - postgres
```

#### 执行初始化脚本
```
psql -f db-init.sql
```

#### 修改配置文件
指定服务器证书和根证书
```
/etc/postgresql/9.4/main/postgresql.conf
ssl_cert_file = '/etc/postgresql-common/server.crt'
ssl_key_file = '/etc/postgresql-common/server.key'
ssl_ca_file = '/etc/postgresql-common/root.pem'
```
强制TCP连接使用SSL
```
/etc/postgresql/9.4/main/pg_hba.conf
# IPv4 local connections:
hostssl    all             all             127.0.0.1/32         cert    clientcert=1
# IPv6 local connections:
hostssl    all             all             ::1/128              cert    clientcert=1
```
#### 启用审计（可选）
此功能可记录SQL操作，详细信息[见此](https://wiki.postgresql.org/wiki/Audit_trigger_91plus)，使用步骤为：

 - 下载audit.sql。目前原项目存在[未修复的问题](https://github.com/2ndQuadrant/audit-trigger/issues/14)，可使用此[临时修复](https://github.com/memoz/audit-trigger/blob/master/audit.sql)。
 - 此功能需要hstore数据类型，安装PostgreSQL附加模块：
```
sudo aptitude install postgresql-contrib
```
 - 以postgres身份在目标数据库（此处为acd）中执行脚本：
```
psql -f audit.sql acd
```
 - 对指定数据表启用审计：
```
SELECT audit.audit_table('数据表名');
```
 - 查询记录：
```
SELECT * FROM audit.logged_actions;
```

### 设置脚本运行环境
#### 安装必须的软件
```
sudo aptitude install tree p7zip-full par2 mailx xmlstarlet postgresql-client python3 python3-lxml python3-pip
sudo pip3 install --upgrade git+https://github.com/yadayada/acd_cli.git
```
#### 放置证书
```
/etc/postgresql-common/postgresql.crt
/etc/postgresql-common/postgresql.key
/etc/postgresql-common/root.pem
```
#### 设置连接服务文件
```
/etc/postgresql-common/pg_service.conf
[dsn1]
dbname=acd
user=packer
host=127.0.0.1
port=5432
connect_timeout=10
client_encoding=utf8
sslmode=verify-full
sslcert=/etc/postgresql-common/postgresql.crt
sslkey=/etc/postgresql-common/postgresql.key
sslrootcert=/etc/postgresql-common/root.pem
```
#### 设置SSH隧道（可选）
如数据库服务器和脚本不在同一系统下运行，可选择直接连接、VPN或SSH隧道等。这里介绍SSH隧道方式。以下称数据库所在机器为服务器，脚本所在机器为客户端。
##### 直连隧道
客户端发起
```
ssh -N -L 5432:127.0.0.1:5432 user@server
```

服务器发起
```
ssh -N -R 5432:127.0.0.1:5432 user@client
```

##### 经第三台机器中转的隧道
客户端发起
```
ssh -N -o "ProxyCommand ssh -W %h:%p user@thirdhost" -L 5432:127.0.0.1:5432 user@server
```

服务器发起
```
ssh -N -o "ProxyCommand ssh -W %h:%p user@thirdhost" -R 5432:127.0.0.1:5432 user@client
```

##### 断线自动重连
 - 使用autossh：参数-f为后台运行；-M为autossh连接监测端口；-N为不执行远程命令，仅建立隧道；环境变量AUTOSSH_POLL为监测数据包发送间隔，单位秒。

```
AUTOSSH_POLL=30 autossh -M 12340 -f -N -o "ProxyCommand ssh -W %h:%p user@thirdhost" -L 5432:127.0.0.1:5432 user@server
```

 - 在服务器设置ClientAliveInterval和ClientAliveCountMax

 - 在客户端设置ServerAliveInterval和ServerAliveCountMax

### 修改脚本参数
#### 电子邮件
请根据自己的情况，修改packer.sh开始处的send_email函数。分为邮件主题、SMTP服务器登陆信息和接收邮箱。
#### savetree.py的时区
此项默认为hours=8，即UTC+8，改为当地偏移量即可。

## 平常使用
将packer.sh和savetree.py放到要保存的文件夹之外，如home。确保home所在分区有足够空间存放压缩包和修复文件。
### 正常上传
```
packer.sh 文件夹名
```

### 从指定步骤开始
一共分为四步：打包（pack）、测试（test）、生成修复文件（par2）和上传（upload）。
```
packer.sh 文件夹名 continue-from-test
```

### 自动判断已完成步骤
此项根据数据库中的status字段确定，功能较弱，详见已知问题。
```
packer.sh 文件夹名 auto-recover
```

### 不在启动时检查数据库连接
此项的目的是便于被其它脚本调用，如依次处理多个文件夹。
```
packer.sh 文件夹名 skip-db-check
packer.sh 文件夹名 auto-recover skip-db-check
```

### 查询数据库
这里需要一个用户界面，暂时用psql代替。
#### 存档列表
```
psql acd
SELECT * FROM summary;
SELECT descr, status FROM summary;
```
#### 目录结构
使用公用表表达式(CTE)
```
WITH RECURSIVE tree AS (
  SELECT node_id, name, parent_id, ARRAY[name] AS item_array
  FROM dir_tree WHERE name = '存档编号'

  UNION ALL

  SELECT dir_tree.node_id, dir_tree.name, dir_tree.parent_id, tree.item_array || dir_tree.name AS item_array
  FROM dir_tree JOIN tree ON (dir_tree.parent_id = tree.node_id)
)
SELECT node_id, array_to_string(item_array, '->') FROM tree ORDER BY item_array;

或者

WITH RECURSIVE tree AS (
  SELECT node_id, ARRAY[]::BIGINT[] AS ancestors FROM dir_tree WHERE name = '存档编号'

  UNION ALL

  SELECT dir_tree.node_id, tree.ancestors || dir_tree.parent_id
  FROM dir_tree, tree
  WHERE dir_tree.parent_id = tree.node_id
)
SELECT * FROM tree INNER JOIN dir_tree USING (node_id) ORDER BY node_id ASC;
```

# 已知问题
## 自动判断进度功能较简单
由于只是读取status字段，对数据库访问失败、用户终止、程序错误、磁盘空间不足、硬件故障等情况无法判断，所以不建议使用。
## 不检查数据库访问失败的原因
目前只是一味进行重试，对非网络原因造成的失败没有进行处理。

# 待完成
将配置参数从代码中分离。

添加数据查询的用户界面。
