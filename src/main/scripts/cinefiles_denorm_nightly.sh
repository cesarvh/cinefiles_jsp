#!/bin/bash
#
# Script for nightly update of cinefiles_denorm tables. Reads a list of
# SQL files (script.list) and submits each file in turn, via psql, to the
# Postgresql database.
#
# To minimize downtime, new tables are created with temporary names.
# After all of the tables have been successfully created, they are
# renamed in a single batch. Then, finally, one more batch file is
# executed to create indexes.
#
# This script should be installed in /home/app_cinefiles_site/src/cinefiles_jsp/src/main/scripts
# SQL files go in /home/app_cinefiles_site/src/cinefiles_jsp/src/main/scripts/sql/denorm_nightly
# Log files go in /home/app_cinefiles_site/log

export BASEDIR=/home/app_cinefiles_site
export BINDIR=$BASEDIR/bin
export SCRIPTDIR=$BASEDIR/src/cinefiles_jsp/src/main/scripts
export PATH=/bin:/usr/bin:$BINDIR:$SCRIPTDIR
export PGUSER=nuxeo_cinefiles
export PGDATABASE=cinefiles_domain_cinefiles
export PGHOST=dba-postgres-prod-42.ist.berkeley.edu
export PGPORT=5313

export SQLDIR="$SCRIPTDIR/sql/denorm_nightly"
export LOGDIR="$BASEDIR/log"
export LOGFILE="$LOGDIR/denorm_nightly.log.$(date +'%d')"
export LOGLEVEL=3

echo  "$(date): running cinefiles_denorm_nightly" >> $LOGDIR/run.log

[ -d "$LOGDIR" ] && [ -n "$LOGFILE" ] && [ "$LOGLEVEL" -gt 0 ] && echo "Starting cinefiles_denorm_nightly at $(date)." > "$LOGFILE"

function notify
{
   echo "NOTIFY: $1" | mail -s "cinefiles denorm" cspace-app-logs@lists.berkeley.edu
}

function log
{
   [ "$LOGLEVEL" -gt 0 ] && [ -f "$LOGFILE" ] && echo "$1" >> $LOGFILE
}

function trace
{
   [ "$LOGLEVEL" -gt 1 ] && [[ -t 0 ]] && echo "TRACE: $1"
   [ "$LOGLEVEL" -gt 2 ] && log "$1"
}

function exit_msg
{
   echo "$1" >&2
   notify "$1"
   exit 1
}

function stripws
{
   r=$(echo "$1 " | sed -e 's/^ *//' -e 's/ *$//')
   echo "${r###*}"
}

function comparetables
{
   re='^[0-9]+ [0-9]+$'
   c1=$1
   c2=$2
   [[ "$c1 $c2" =~ $re ]] && return 0
   return 1;
}

update_status=0
STATUSMSG="ALL DONE"
linecount=0

while read FILE
do
   linecount=$((linecount + 1))
   trace "${linecount}) READING: $FILE"

   SQLFILE="$(stripws "$FILE")"
   [ -n "$SQLFILE" ] || continue

   trace "USING: $(ls -l ${SQLDIR}/${SQLFILE})"

   result=$(psql -q -t -f "${SQLDIR}/${SQLFILE}")
   trace "RESULT: $result"

   if ! comparetables $result
   then
      update_status=$((update_status+1))
      STATUSMSG="Table counts DO NOT agree for $SQLFILE. (Status: $update_status)"
      log $STATUSMSG
   else
      trace "Table counts DO agree for $SQLFILE. (Status: $update_status)"
   fi
done < "${SQLDIR}/script.list"

trace "DONE LOOPING, STATUS = $update_status"

if [ "$update_status" -eq 0 ]
then
   trace "GETTING TABLE COUNTS"
   psql -q -t -f "${SQLDIR}/checkalltables.sql" > "${LOGDIR}/checkalltables.out" 2>&1
   trace "RENAMING TEMP TABLES (STATUS: $update_status)"
   result=$(psql -q -t -f "${SQLDIR}/rename_all.sql")
   log "RENAMED ALL FILES (STATUS: $update_status)"
   trace "CREATING INDEXES"
   result=$(psql -q -t -f "${SQLDIR}/create_indexes.sql")
else
   trace "BAILING"
   notify "$STATUSMSG (STATUS: $update_status)"
   exit_msg "$STATUSMSG (STATUS: $update_status)"
fi

FILE="originaljpegs.sql"
SQLFILE="$(stripws "$FILE")"

if [ -n "$SQLFILE" ]
then
   trace "USING: $(ls -l ${SQLDIR}/${SQLFILE})"
   result=$(psql -q -t -f "${SQLDIR}/${SQLFILE}")
   trace "RESULT: $result"
else
   trace "SKIPPING $FILE"
fi

trace "ALL DONE at `date`"

