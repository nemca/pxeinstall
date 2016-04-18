#! /usr/bin/env bash
# Logging 
_timeNow() {
        date +"%Y-%m-%d %H:%M:%S"
}

log() {
        if [[ -z ${log_file} ]]; then
                echo "`_timeNow` [INFO] $1"
        else
                echo "`_timeNow` [INFO] $1" >> ${log_file}
        fi
}

error() {
        if [[ -z ${log_file} ]]; then
                echo "`_timeNow` [ERROR] $1"
        else
                echo "`_timeNow` [ERROR] $1" >> ${log_file}
        fi
        if [[ -n ${MAILTO} ]]; then
                echo "`_timeNow` [ERROR] $1" | mail -s "[ERROR] `basename $0` on `hostname -f`" ${MAILTO}
        fi
        exit 1
}

warning() {
        if [[ -z ${log_file} ]]; then
                echo "`_timeNow` [WARNING] $1"
        else
                echo "`_timeNow` [WARNING] $1" >> ${log_file}
        fi
}
