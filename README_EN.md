# acd-scripts
Amazon Cloud Drive (ACD) is a personal network drive service from Amazon. The scripts in this project wrap around some softwares under shell for easy big folder uploading.

# Features
 - Do volume compression, encryption, testing, adding recovery files and uploading automatically to a given folder, and save the directory structure, password and other info to PostgreSQL database.
 - Send email notifications for errors and completion.
 - Optional auto or manual step selections for interruption recovery.

# Files
    Name    |  Language  |   Functions
----------- | ---------- | ------------
packer.sh   | GNU Bash   | Main program
savetree.py | Python 3   | Convert xml directory tree to adjacency list
db-init.sql | PostgreSQL | Create database

# Dependencies
Apart from GNU Core Utils, we need：

   Softwares   |   Purposes
-------------- | ------------
tree           | Extract directory tree
p7zip          | Compression and encryption
par2           | Generate recovery files
heirloom-mailx | Send emails
xmlstarlet     | Parse xml files
psql           | Access database
acd_cli        | Uplaod to ACD
[acd_cli](https://github.com/yadayada/acd_cli) is another Github project, others are free softwares。

# Usage
I'm on Debian Jessie. Use your distribution's package manager where appropriate. Configuration files may reside elsewhere.
## First use
### Generate self-signed digital certificates
To replace database password authentication.
#### Root Certification Authority
```
openssl genrsa -out rootCA.key 2048
openssl req -x509 -new -nodes -key rootCA.key -days 1024 -out rootCA.pem
```
#### Issue client and server certificates
Change "device" to corresponding names such as "client" and "server". The "Common Name(FQDN)" field needs to be filled with username for client, domain name or IP address for server.
```
openssl genrsa -out device.key 2048
openssl req -new -key device.key -out device.csr
openssl x509 -req -in device.csr -CA root.pem -CAkey rootCA.key -CAcreateserial -out device.crt -days 500
```
### Set up database server
#### Install PostgreSQL
```
sudo aptitude install postgresql
```

#### Switch to user postgres
```
sudo su - postgres
```

#### Initialize database
```
psql -f db-init.sql
```

#### Modify configuration files
Specify server cert and root cert
```
/etc/postgresql/9.4/main/postgresql.conf
ssl_cert_file = '/etc/postgresql-common/server.crt'
ssl_key_file = '/etc/postgresql-common/server.key'
ssl_ca_file = '/etc/postgresql-common/root.pem'
```
Force SSL on TCP connections
```
/etc/postgresql/9.4/main/pg_hba.conf
# IPv4 local connections:
hostssl    all             all             127.0.0.1/32         cert    clientcert=1
# IPv6 local connections:
hostssl    all             all             ::1/128              cert    clientcert=1
```
#### Enable auditing (optional)
This feature keeps a log of certain SQL transactions. See [here](https://wiki.postgresql.org/wiki/Audit_trigger_91plus) for details. To use it:

 - Download audit.sql. This project has [an open issue](https://github.com/2ndQuadrant/audit-trigger/issues/14). A [temporary fix](https://github.com/memoz/audit-trigger/blob/master/audit.sql) is available.
 - This feature requires hstore data type. Install additional PostgreSQL modules:
```
sudo aptitude install postgresql-contrib
```
 - Execute the script as user postgres on the target database acd:
```
psql -f audit.sql acd
```
 - Enable auditing for a table:
```
SELECT audit.audit_table('table name');
```
 - Read the logs:
```
SELECT * FROM audit.logged_actions;
```

### Set up scripts' environment
#### Install required softwares
```
sudo aptitude install tree p7zip-full par2 mailx xmlstarlet postgresql-client python3 python3-lxml python3-pip
sudo pip3 install --upgrade git+https://github.com/yadayada/acd_cli.git
```
#### Place client certificates
```
/etc/postgresql-common/postgresql.crt
/etc/postgresql-common/postgresql.key
/etc/postgresql-common/root.pem
```
#### Set up client connection service file
So we can simply pass a "name" to psql.
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
#### Set up SSH tunnel (optional)
If the scripts run on a different machine(client) from the database server(server), we have the options of direct connection, VPN, SSH tunnels and more. Here's how to set up SSH tunnels.
##### Direct tunnel
From client's end
```
ssh -N -L 5432:127.0.0.1:5432 user@server
```

From server's end
```
ssh -N -R 5432:127.0.0.1:5432 user@client
```

##### Passing through a third machine
From client's end
```
ssh -N -o "ProxyCommand ssh -W %h:%p user@thirdhost" -L 5432:127.0.0.1:5432 user@server
```

From server's end
```
ssh -N -o "ProxyCommand ssh -W %h:%p user@thirdhost" -R 5432:127.0.0.1:5432 user@client
```

##### Auto reconnect
 - Use autossh: -f fall into background; -M autossh monitor port; -N do not execute remote commands, tunnel only; environment variable AUTOSSH_POLL, monitor packet sending interval in seconds.

```
AUTOSSH_POLL=30 autossh -M 12340 -f -N -o "ProxyCommand ssh -W %h:%p user@thirdhost" -L 5432:127.0.0.1:5432 user@server
```

 - Set ssh options ClientAliveInterval and ClientAliveCountMax on the server.

 - Set ssh options ServerAliveInterval and ServerAliveCountMax on the client.

### Change script parameters
#### Email
Modify send_email function at the beginning of packer.sh to set subject, SMTP server and recepient.
#### savetree.py timezone
Default setting is hours=8 ie. UTC+8. Change it accordingly.

## Subsequent usage
Save packer.sh and savetree.py in a convenient place outside the target directory, such as home directory. Make sure the home partition has enough free space for the archive and recovery files.
### Normal uploading
```
packer.sh directory_name
```

### Start from a certain step
There are 4 steps: pack, test, par2 and upload.
```
packer.sh directory_name continue-from-test
```

### Auto check for start steps
This function reads the "status" field from the database, so it's rather weak. See known issues.
```
packer.sh directory_name auto-recover
```

### Disable database connection check on startup
This option is aimed at batch processing(by invoking this script), so temporary network issues don't cause unnecessary interruptions.
```
packer.sh directory_name skip-db-check
packer.sh directory_name auto-recover skip-db-check
```

### Querying the database
This should be a separate feature, but we'll use psql for now. 
#### Archive list
```
psql acd
SELECT * FROM summary;
SELECT descr, status FROM summary;
```
#### Directory structures
Using Common Table Expressions(CTE)
```
WITH RECURSIVE tree AS (
  SELECT node_id, name, parent_id, ARRAY[name] AS item_array
  FROM dir_tree WHERE name = 'Archive Number'

  UNION ALL

  SELECT dir_tree.node_id, dir_tree.name, dir_tree.parent_id, tree.item_array || dir_tree.name AS item_array
  FROM dir_tree JOIN tree ON (dir_tree.parent_id = tree.node_id)
)
SELECT node_id, array_to_string(item_array, '->') FROM tree ORDER BY item_array;

Or we can use this:

WITH RECURSIVE tree AS (
  SELECT node_id, ARRAY[]::BIGINT[] AS ancestors FROM dir_tree WHERE name = 'Archive Number'

  UNION ALL

  SELECT dir_tree.node_id, tree.ancestors || dir_tree.parent_id
  FROM dir_tree, tree
  WHERE dir_tree.parent_id = tree.node_id
)
SELECT * FROM tree INNER JOIN dir_tree USING (node_id) ORDER BY node_id ASC;
```

# Known issues
## Weak auto step check
Reading only the "status" field from database makes it impossible to check for database access failures, user interruptions, programming errors, insufficient disk space, hardware failures and so on, so don't rely on it.
## Not checking why database access failed
It's only endless retries now. Should account for errors other than network.

# TODO
 - Separate configurations from the code.
 - Implement a user interface for database look ups.
