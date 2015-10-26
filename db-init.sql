-- Copyright (C) 2015  Bowen Jiang  (unctas@gmail.com)
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

-- 创建脚本用户packer
-- Create script user packer
CREATE ROLE packer WITH LOGIN CONNECTION LIMIT 1;

-- 创建普通用户usr1
-- Create ordinary user usr1
CREATE ROLE usr1 WITH LOGIN;

-- 创建据库acd
-- Create database acd
CREATE DATABASE acd WITH TEMPLATE=template0;

-- 连接至新数据库
-- Connect to new database
\c acd

-- 创建数据表1，summary
-- Create table1, summary
CREATE TABLE summary (
    arc_no BIGINT PRIMARY KEY,
    vols INTEGER,
    aprnt_size BIGINT,
    act_size BIGINT,
    dirs INTEGER,
    files INTEGER,
    status TEXT,
    password TEXT,
    descr TEXT,
    rem TEXT
) WITH (OIDS=FALSE);

-- 创建数据表2，dir_tree
-- Create table2, dir_tree
CREATE TABLE dir_tree (
    node_id BIGSERIAL PRIMARY KEY,
    name TEXT,
    size BIGINT,
    is_dir BOOLEAN DEFAULT FALSE,
    parent_id BIGINT REFERENCES dir_tree(node_id) ON DELETE CASCADE ON UPDATE CASCADE
) WITH (OIDS=FALSE);

-- 授权用户访问
-- Grant access to users
GRANT INSERT, SELECT, UPDATE ON summary TO packer, usr1;
GRANT INSERT, SELECT ON dir_tree TO packer;
GRANT SELECT ON dir_tree TO usr1;
GRANT UPDATE ON dir_tree_node_id_seq TO packer;

-- 创建函数query_arc_name，查询存档名
-- Create function query_arc_name to lookup archive names
CREATE FUNCTION query_arc_name() RETURNS TRIGGER AS $query_arc_name$
    BEGIN
        -- Check if this archive exists in the summary table
        IF (SELECT EXISTS(SELECT arc_no FROM summary WHERE arc_no = CAST(NEW.name AS BIGINT))) THEN
            RETURN NEW;
        END IF;
        RAISE EXCEPTION 'Archive % does not exist in the summary table!', NEW.name
            USING HINT = 'Have you added that record?';
    END;
$query_arc_name$ LANGUAGE plpgsql;

-- 创建触发器chk_arc_exist，检查目录树起点的参照完整性
-- Create trigger chk_arc_exist to check cross table referential integrity of tree root
CREATE TRIGGER chk_arc_exist
    BEFORE INSERT OR UPDATE ON dir_tree
    FOR EACH ROW
    WHEN (NEW.parent_id IS NULL)
    EXECUTE PROCEDURE query_arc_name();

-- 启用审计
-- Enable auditing
-- \i ~/scripts/audit.sql
-- SELECT audit.audit_table('summary');
