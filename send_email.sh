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

# 发送通知邮件
# Send notification emails
function send_email () {
    if [ -f "$1" ]; then
        cat "$1"
        mailx \
        -s "subject" \
        -S smtp="smtp.gmail.com:587" \
        -S smtp-use-starttls \
        -S smtp-auth=login \
        -S smtp-auth-user="user@example.com" \
        -S smtp-auth-password="password" \
        -S ssl-verify=ignore \
        user@example.com < "$1"
    else
        echo "$1" | mailx \
        -s "subject" \
        -S smtp="smtp.gmail.com:587" \
        -S smtp-use-starttls \
        -S smtp-auth=login \
        -S smtp-auth-user="user@example.com" \
        -S smtp-auth-password="password" \
        -S ssl-verify=ignore \
        user@example.com
    fi
    if [ $? -ne 0 ]; then
        echo -e "FAILED to send email!"
        exit 1
    fi
}
