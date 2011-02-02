#!/bin/bash 
#===============================================================================
#
#          FILE:  mysql_backups.sh
#
#         USAGE:  ./mysql_backups.sh ARGUMENT
#
#   DESCRIPTION:  Creates mysqldumps of all databases with bzip2 compression
#                 and / or save the mysql binaries.
#
#                 After execution a symbolic link named CURRENT will be set into ${BACKUP_DIR}
#                 which points to ${DATESTAMP}.
#
#       ARGUMENTS: --databases  Creates mysqldumps for all databases (on file per database). 
#                              The files will  be saved in ${BACKUP_DIR}/${DATESTAMP}/databases.
#                              Result file pattern: {database}.sql.bz2.
#
#                 --tables     Creates mysqldumps for all tables of all databases 
#                              (seperate file for each table)                 
#                              The files will  be saved in ${BACKUP_DIR}/${DATESTAMP}/tables.
#                              Result file pattern: ${database}.${table}.sql.bz2.
#
#                 --both       Combines --tables with --databases 
#
#                 --bin        Copies the binary files of mysql. 
#                              The mysql service will stopped before copying the file
#                              and will be started again after copying.
#                              The files will  be saved in ${BACKUP_DIR}/${DATESTAMP}/bin.
#
#                 --all        Combines --both with --bin.
#
#           		  --purge      Purges the amount of dumps which is greater (and older) 
#			                         than $HOLD_DUMPS (default 30)  -1 (the CURRENT symlink)
#
#  REQUIREMENTS:  mysql, mysqldump, bzip2, /root/.my.cnf with mysql-root credential
#                 executed under root uid
#
#          BUGS:  ---
#         NOTES:  ---
#        AUTHOR: Florian Latzel (ISL/FL), florian.latzel@is-loesungen.de
#       COMPANY: ISL Individuelle System Lösungen
#       CREATED: 03/23/2010 12:14:57 PM CET
#      REVISION: $Id:
#===============================================================================


# Variables
BASENAME=`basename $0`
BACKUP_DIR="/var/mysql_backups"
DATESTAMP=`date +%FT%R`
BACKUP_PATH="${BACKUP_DIR}/${DATESTAMP}"
MYSQL_BIN_DIR='/var/lib/mysql/'
HOLD_DUMPS=30


# Binaries
mysql='/usr/bin/mysql'
mysqldump='/usr/bin/mysqldump'
bzip2='/bin/bzip2'
mysql_service='/etc/init.d/mysql'

# set umask for backup files and directories
umask 0077

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_help
#   DESCRIPTION:  Help function
#    PARAMETERS:  -
#       RETURNS:  1
#===============================================================================
mysql_backup_help () {
  echo -e "Usage: ${BASENAME} --databases | --tables | --both | --bin | --all | --purge "
  echo -e "ARGUMENTS:"
  echo -e "--databases \n \
  Creates mysqldumps for all databases (on file per database).\n \
  The files will  be saved in \${BACKUP_DIR}/\${DATESTAMP}/databases.\n \
  Result file pattern: {database}.sql.bz2.\n\n \
--tables\n \
  Creates mysqldumps for all tables of all databases\n \
  (seperate file for each table)\n \
  The files will  be saved in \${BACKUP_DIR}/\${DATESTAMP}/tables.\n \
  Result file pattern: \${database}.\${table}.sql.bz2.\n\n \
--both\n \
  Combines --tables with --databases\n\n \
--bin\n \
  Copies the binary files of mysql.\n \
  The mysql service will stopped before copying the file\n \
  and will be started again after copying.\n \
  The files will  be saved in \${BACKUP_DIR}/\${DATESTAMP}/bin.\n\n \
--all\n \
  Combines --both with --bin.\n\n \
--purge\n \
  Purges the amount of dumps which is greater (and older)\n \
  than \$HOLD_DUMPS (default 30)  -1 (the CURRENT symlink)"
  return 1
}


#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_checks
#   DESCRIPTION:  Checks for uid, should be 0,
#                 if /root/.my.cnf does exist 
#                 and for valid options.
#                 Calles mysql_backup_help if there are invalid options.
#    PARAMETERS:  -
#       RETURNS:  0 if all checks were successful,
#                 2 if uid != 0 (root) or 
#                 3 if /root/.my.cnf does not exist
#===============================================================================
mysql_backup_checks () {
  # checking /root/.my.cnf
  if [ ! -f "${HOME}/.my.cnf" ] ; then
    echo "Can not find required .my.cnf in $HOME" 1>&2
    return 3
  fi
  # checking parameter
  if [ "${#}" -ne 1 ] ; then    
    echo "Expecting Argument, do not know what to do..." 1>&2
  fi
  case "${1}" in 
  "--databases" | "--tables" | "--both" | "--bin" | "--all" | "--purge" )
    return 0
    ;;
  "--help" | *) 
    mysql_backup_help
    ;;
  esac
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_get_databases
#   DESCRIPTION:  Return all found mysql databases
#    PARAMETERS:  -
#       RETURNS:  All found mysql databases without column names with exit 0
#                 or 4 if the mysql command failed.
#===============================================================================
mysql_backup_get_databases ()  {
  DATABASES=`$mysql --skip-column-names <<< "show databases;"`
  [ "${?}" -ne 0 ] && return 4
  echo $DATABASES
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_get_tables
#   DESCRIPTION:  Return all tables of the supplied database.
#    PARAMETERS:  $DATABASE
#       RETURNS:  All tables of the specified database without column names with exit 0
#                 or 5 if the mysql command failed.
#===============================================================================
mysql_backup_get_tables ()  {
  TABLES=`$mysql --skip-column-names <<< "use ${1}; show tables;"`
  [ "${?}" -ne 0 ] && return 5
  echo $TABLES
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_tables
#   DESCRIPTION:  Backup the supplied database tablewise 
#                 in ${BACKUP_DIR}/${DATESTAMP}
#                 and commpress them with bzip2
#                 Result file pattern: ${DATABASE}.${TABLE}.sql.bz2
#    PARAMETERS:  $DATABASE
#       RETURNS:  0 if successfull,
#                 6 if mkdir failed or 7 if mysqldump failed
#===============================================================================
mysql_backup_tables ()  {
  for TABLE in `mysql_backup_get_tables $1` ; do
    DIR="${BACKUP_PATH}/tables/${DATABASE}"
    FILE="${DIR}/${DATABASE}.${TABLE}.sql"
    if [ "${TABLE}" != Tables_in_${DATABASE} ] ; then
      mkdir -p $DIR || return 6
      $mysqldump $DATABASE $TABLE > $FILE || return 7
      [ -f "${FILE}.bz2" ] && rm "${FILE}.bz2"
      $bzip2 $FILE
    fi
  done
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_database
#   DESCRIPTION:  Backup the supplied database bzip2 compressed 
#                 in ${BACKUP_DIR}/${DATESTAMP}
#                 Result file pattern: ${DATABASE}.sql.bz2  
#    PARAMETERS:  $DATABASE
#       RETURNS:  0 if successfull,
#                 6 if mkdir failed or 7 if mysqldump failed
#===============================================================================
mysql_backup_database ()  {
  DATABASE=$1
  DIR="${BACKUP_PATH}/databases"
  FILE="${DIR}/${DATABASE}.sql"
  mkdir -p "${DIR}" || return 6
  # @see http://forums.mysql.com/read.php?10,108835,108835
  # ERROR: Access denied for user 'root'@'localhost' to database 'information_schema' when using LOCK TABLES
  if [ ${DATABASE} = 'information_schema' ] ; then
    mysqldump --skip-lock-tables ${DATABASE} > "${FILE}" || return 7
  else 
    mysqldump ${DATABASE} > "${FILE}" || return 7
  fi 
  [ -f "${FILE}.bz2" ] && rm "${FILE}.bz2"
  bzip2 "${FILE}"
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_bin
#   DESCRIPTION:  Backup mysql's bin files after stopping mysql service
#                 and restart it after copying.
#    PARAMETERS:  -
#       RETURNS:  0 if successfull,
#                 8 if stopping mysql failed or 9 if (re)starting mysql failed.
#===============================================================================
mysql_backup_bin ()  {
  DIR="${BACKUP_PATH}/bin"
  mkdir -p $DIR
  $mysql_service stop && cp -r ${MYSQL_BIN_DIR}* $DIR || return 8
  $mysql_service start || return 9
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_symlink
#   DESCRIPTION:  Create a symbolic link in ${BACKUP_DIR} named CURRENT
#                 which points to ${DATESTAMP}, which contains the latest backups.
#    PARAMETERS:  -
#       RETURNS:  0 if successfull,
#                 10 if unlink of existing CURRENT failed 
#                 or 11 if the creation the symlink failed.
#===============================================================================
mysql_backup_symlink () {
  if [ -L "${BACKUP_DIR}/CURRENT" ] ; then
    unlink "${BACKUP_DIR}/CURRENT" || return 10
  fi
  cd ${BACKUP_DIR}
  ln -s ${DATESTAMP} CURRENT || return 11
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  mysql_backup_purge
#   DESCRIPTION:  Purges the amount of dumps that is greater then $HOLD_DUMPS -1
#    PARAMETERS:  -
#       RETURNS:  0 if purge was successfull or no files to purge
#                 12 if unable to traverse to $BACKUP_DIR
#                 or 13 if deletion of $purge_files failed.
#===============================================================================
mysql_backup_purge () {
  cd ${BACKUP_DIR} || return 12
  dump_count=`ls -A1 | wc -l`
  if [ "${dump_count}" -gt "`expr ${HOLD_DUMPS} + 1`" ] ; then 
    dump_count=`expr ${dump_count} - 1` # -1 for CURRENT Symlink
    purge_lines=`expr ${dump_count} - ${HOLD_DUMPS}`
    purge_files=`ls -A1 | head -n ${purge_lines}`
    rm -r ${purge_files} && echo "Purged $purge_files" || return 13
  fi
  return 0
}

#===  FUNCTION  ================================================================
#          NAME:  main
#   DESCRIPTION:  Main function
#    PARAMETERS:  $@
#       RETURNS:  Integer
#===============================================================================
main ()  {
  mysql_backup_checks $@ || return $?
  # Dumps incl. setting the symlink
  if [ "${1}" = "--databases" -o "${1}" = "--tables" -o "${1}" = "--both" -o "${1}" = "--bin" -o "${1}" = "--all" ] ; then
    DATABASES=`mysql_backup_get_databases`
    for DATABASE in ${DATABASES};  do
      if [ "${1}" = "--databases" ] ; then
        mysql_backup_database $DATABASE || return $?
      fi
      if [ "${1}" = "--tables" ] ; then
        mysql_backup_tables $DATABASE || return $?
      fi
      if [ "${1}" = "--both" -o "${1}" = "--all" ] ; then
        mysql_backup_database $DATABASE || return $?
        mysql_backup_tables $DATABASE || return $?
      fi
    done
    if [ "${1}" = "--bin" -o "${1}" = "--all" ] ; then
      mysql_backup_bin || return $?
    fi
    mysql_backup_symlink || return $?
  # Purging old dumps
  elif ["${1}" = "--purge" ] ; then
    mysql_backup_purge || return $?
  fi
  return 0
}

main $@   # run main function
exit $?   # exit with latest exit status of main
