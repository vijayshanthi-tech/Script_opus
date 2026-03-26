$!
$  SET VERIFY
$!**********************************************************************************************************
$!              COMMAND FILE: TAP_RSERCFILES_TRANSFER.COM
$!**********************************************************************************************************
$! MODIFICATION HISTORY :
$! ====================
$!
$!    DATE           AUTHOR               DESCRIPTION
$!
$! 30-07-2018      MAHALAKSHMI        This job will transfer the generated RSERC and MRLOG files from TAP
$!                                    to ABS through SFTP.
$! 30-03-2019      ARUL MANI          Added temporary file location and file extension to aviod files being
$!                                    picked while transfer in progress. Also added self recovery.
$!
$! 14-11-2018      MAHALAKSHMI        Modified to transfer the RSERC files from FCS_RSERC_DIR directory
$!                                    instead of XI_DAT directory.
$!
$!
$!**********************************************************************************************************
$!
$!              Input files        :    RSERC%%%%%%.DAT;*
$!                                      MRLOG%%%%%%.DAT;*
$!
$!             File Transfer mode :     SFTP
$!
$!------------------------------------------------------------------------------------------------------------
$!              SAVE CURRENT ENVIRONMENT
$!
$ SAVE_ENVIRONMENT:
$!================
$!
$       phase           =       "SAVE_ENVIRONMENT"
$!
$       procname        =       f$parse("''f$environment(""PROCEDURE"")'",,,"NAME")
$!
$       WSO             ==      "write sys$output"
$       CSI[0,8]        =       %D155
$       ESC[0,8]        =       %D27
$       OPERATOR        ==      "OPER8"
$       REV             =       "''CSI'7m"
$       OFF             =       "''CSI'0m"
$       message         =       ""
$       status          ==      ""
$       email_flag      =       "Y"
$       nodename        =       f$getsyi("nodename")
$!
$       contcodes       =       f$environment("control")
$       messcodes       =       f$environment("message")
$       def_dir         =       f$environment("default")
$!
$       verify          =       f$verify(1)
$       set control     =       (t,y)
$!
$!=========================================================================================================
$!              DEFINE ERROR SECTION
$!=========================================================================================================
$!
$       ON ERROR THEN GOTO ERROR
$       ON WARNING THEN CONTINUE
$       SET NOON
$       SET VERIFY
$!
$!=========================================================================================================
$!              AVOID MULTIPLE INSTANCES
$!=========================================================================================================
$!
$ CHECK_INSTANCES:
$!===============
$!
$       phase       = "Check instance"
$!
$       @tap_com_dir:taplog_mess "    " "''procname' has started at ''F$TIME()'"
$       current_process = "RSERC_TRANS"
$       SET PROCESS /NAME='current_process'
$!
$       IF .NOT. $STATUS
$       THEN
$               status = "''current_process' exiting - process already running."
$               GOTO ERROR
$       ENDIF
$!
$!=========================================================================================================
$!              CHECK FOR THE LOGICALS AND CONFIG FILE
$!=========================================================================================================
$!
$       IF F$TRNLNM("TAP_CFG_DIR") .EQS. ""
$       THEN
$               STATUS  = "*** Fatal: Unable to find logical - TAP_CFG_DIR."
$               GOTO ERROR
$       ENDIF
$!
$       IF F$TRNLNM("XI_DAT")   .EQS. ""
$       THEN
$               STATUS  = "*** Fatal: Unable to find logical - XI_DAT."
$               GOTO ERROR
$       ENDIF
$!
$       IF F$TRNLNM("FCS_RSERC_DIR")   .EQS. ""
$       THEN
$               STATUS  = "*** Fatal: Unable to find logical - FCS_RSERC_DIR."
$               GOTO ERROR
$       ENDIF
$!
$       IF F$TRNLNM("RSERC_TRANS_SHUTDOWN")   .EQS. ""
$       THEN
$               STATUS  = "*** Fatal: Unable to find logical - RSERC_TRANS_SHUTDOWN."
$               GOTO ERROR
$       ENDIF
$!
$       SFTP_CFG_FILE=F$SEARCH("TAP_CFG_DIR:RSERC_SFTP.CFG;*")
$!
$       IF SFTP_CFG_FILE  .EQS. ""
$       THEN
$                STATUS =" ERROR WHILE SEARCHING FOR TAP_CFG_DIR:RSERC_SFTP.CFG;* FILE "
$                GOTO ERROR
$       ENDIF
$!
$       IF F$TRNLNM("SFTP_TMP_DIR") .EQS. ""
$       THEN
$                STATUS = "*** Fatal: Unable to find logical - SFTP_TMP_DIR"
$                GOTO ERROR
$       ENDIF
$!
$!=========================================================================================================
$!              HOUSE KEEPING
$!=========================================================================================================
$!
$ HOUSE_KEEP:
$!==========
$!
$       PHASE   =       "HOUSE_KEEP"
$!
$       DELETE/BEFORE="TODAY-7-00" TAP_LOG_DIR:TAP_RSERCFILES_TRANSFER.LOG;*
$!
$!=========================================================================================================
$!              EXTRACT SFTP DETAILS
$!=========================================================================================================
$!
$ EXTRACT_SFTP:
$!============
$!
$       OPEN/READ    SFTP_TMP_FILE     TAP_CFG_DIR:RSERC_SFTP.CFG;
$       READ         SFTP_TMP_FILE     DESTUSERNAME
$       READ         SFTP_TMP_FILE     DESTHOSTNAME
$       CLOSE        SFTP_TMP_FILE
$!
$!=========================================================================================================
$!              SELF RECOVERY
$!=========================================================================================================
$!
$ SELF_RECOVERY:
$!=============
$!
$       PHASE   =       "SELF_RECOVERY"
$!
$       DELETE SFTP_TMP_DIR:*.*;*
$       RECOVER_FILE=F$SEARCH("TAP_DAT_DIR:SFTP_ABS_IN_PROGRESS.FLAG;*")
$       IF RECOVER_FILE .EQS. ""
$       THEN
$                GOTO MAIN_PARA
$       ENDIF
$       DELETE/LOG TAP_DAT_DIR:SFTP_ABS_IN_PROGRESS.FLAG;*
$!
$ RECOVERY_1:
$!
$       CTRL_FILE=F$SEARCH("TAP_DAT_DIR:SFTP_CTRL_FILE.DAT;*")
$       IF CTRL_FILE .EQS. ""
$       THEN
$                GOTO RECOVERY_2
$       ENDIF
$!
$       OPEN/WRITE      SFTP_RECOVER_FILE    TAP_DAT_DIR:SFTP_RECOVER_FILE.DAT;
$       WRITE           SFTP_RECOVER_FILE    "cd xi_dat"
$       WRITE           SFTP_RECOVER_FILE    "rm *.SFTP_TMP_RS;*"
$       WRITE           SFTP_RECOVER_FILE    "exit"
$       CLOSE           SFTP_RECOVER_FILE
$!
$       SFTP      -b    TAP_DAT_DIR:SFTP_RECOVER_FILE.DAT      "''destusername'@''desthostname'"
$!
$       IF .NOT. $STATUS
$       THEN
$              STATUS = "ERROR WHILE RECOVERING THE PREVIOUS FAILURE - Remove SFTP PROCESS"
$              GOTO ERROR
$       ENDIF
$       DELETE/LOG TAP_DAT_DIR:SFTP_RECOVER_FILE.DAT;*
$       DELETE/LOG TAP_DAT_DIR:SFTP_CTRL_FILE.DAT;*
$       DELETE/LOG TAP_DAT_DIR:RENAME_SFTPD_FILES_TMP.COM;*
$       DELETE/LOG TAP_DAT_DIR:DELETE_SFTPD_FILES_TMP.COM;*
$       GOTO MAIN_PARA
$!
$ RECOVERY_2:
$!
$       REN_FILE=F$SEARCH("TAP_DAT_DIR:RENAME_SFTPD_FILES_TMP.COM;*")
$       IF REN_FILE .EQS. ""
$       THEN
$                GOTO RECOVERY_3
$       ENDIF
$!
$!       OPEN/WRITE      SFTP_REN_RECOVER_FILE    TAP_DAT_DIR:SFTP_REN_RECOVER_FILE.DAT;
$!       WRITE           SFTP_REN_RECOVER_FILE    "cd xi_dat"
$!       WRITE           SFTP_REN_RECOVER_FILE    "rename *.SFTP_TMP_RS;* *.DAT;*"
$!       WRITE           SFTP_REN_RECOVER_FILE    "exit"
$!       CLOSE           SFTP_REN_RECOVER_FILE
$!
$!       SFTP      -b    TAP_DAT_DIR:SFTP_REN_RECOVER_FILE.DAT      "''destusername'@''desthostname'"
$!
$!       IF .NOT. $STATUS
$!       THEN
$              STATUS = "ERROR WHILE RECOVERING THE PREVIOUS FAILURE - Rename SFTP PROCESS"
$              GOTO ERROR
$!       ENDIF
$!       DELETE/LOG TAP_DAT_DIR:SFTP_REN_RECOVER_FILE.DAT;*
$!       DELETE/LOG TAP_DAT_DIR:RENAME_SFTPD_FILES_TMP.COM;*
$!
$ RECOVERY_3:
$!
$       DEL_FILE=F$SEARCH("TAP_DAT_DIR:DELETE_SFTPD_FILES_TMP.COM;*")
$       IF DEL_FILE .EQS. ""
$       THEN
$                GOTO MAIN_PARA
$       ENDIF
$!
$       @TAP_DAT_DIR:DELETE_SFTPD_FILES_TMP.COM;
$       IF .NOT. $STATUS
$       THEN
$                STATUS = "ERROR WHILE RECOVERING THE PREVIOUS FAILURE - Delete in TAP XI_DAT"
$                GOTO ERROR
$       ENDIF
$!
$!=========================================================================================================
$!              MAIN PARA
$!=========================================================================================================
$!
$!
$ MAIN_PARA:
$!=========
$!
$       PHASE   =       "MAIN PARA"
$!
$ MAIN_LOOP:
$!
$       OPEN/WRITE      SFTP_CTRL_FILE       TAP_DAT_DIR:SFTP_CTRL_FILE.DAT;
$       WRITE           SFTP_CTRL_FILE       "binary"
$       WRITE           SFTP_CTRL_FILE       "lcd SFTP_TMP_DIR"
$       WRITE           SFTP_CTRL_FILE       "cd xi_dat"
$!
$       OPEN/WRITE      RENAME_TMP_FILE      TAP_DAT_DIR:RENAME_SFTPD_FILES_TMP.COM;
$       WRITE           RENAME_TMP_FILE      "cd xi_dat"
$       OPEN/WRITE      DELETE_TMP_FILE      TAP_DAT_DIR:DELETE_SFTPD_FILES_TMP.COM;
$!
$       RSERC_COUNT = 0
$       MRLOG_COUNT = 0
$!
$ RSERC_FILE_COUNT:
$!
$       RSERC_FILE = F$SEARCH ("FCS_RSERC_DIR:RSERC%%%%%%.DAT;*",1)
$       FILENAME = F$EXTRACT(F$LOCATE("]",RSERC_FILE)+1,150,RSERC_FILE)
$       name     = f$parse(FILENAME,,,"name")
$       version  = f$parse(FILENAME,,,"version")
$       FILE_TMP = name+".SFTP_TMP_RS"+version
$!
$       IF RSERC_FILE  .EQS. ""
$       THEN
$               GOTO MRLOG_FILE_COUNT
$       ENDIF
$!
$       RSERC_COUNT = RSERC_COUNT + 1
$       IF RSERC_COUNT .GT. 50
$       THEN
$               GOTO MRLOG_FILE_COUNT
$       ELSE
$               COPY/LOG 'RSERC_FILE SFTP_TMP_DIR:'FILE_TMP
$               WRITE  SFTP_CTRL_FILE "put ''FILE_TMP'"
$               WRITE  RENAME_TMP_FILE "rename ''FILE_TMP' ''FILENAME'"
$               WRITE  DELETE_TMP_FILE "$DELETE/LOG FCS_RSERC_DIR:''FILENAME'"
$               GOTO RSERC_FILE_COUNT
$       ENDIF
$!
$ MRLOG_FILE_COUNT:
$!
$       MRLOG_FILE = F$SEARCH ("XI_DAT:MRLOG%%%%%%.DAT;*",2)
$       FILENAME = F$EXTRACT(F$LOCATE("]",MRLOG_FILE)+1,16,MRLOG_FILE)
$       name     = f$parse(FILENAME,,,"name")
$       version  = f$parse(FILENAME,,,"version")
$       FILE_TMP = name+".SFTP_TMP_RS"+version
$!
$       IF MRLOG_FILE .EQS. ""
$       THEN
$               IF (RSERC_COUNT .GT. 0) .OR. (MRLOG_COUNT .GT. 0)
$               THEN
$                       GOTO SFTP_PROCESS
$               ELSE
$                       WAIT 00:10:00
$                       GOTO FINAL_CHECK
$               ENDIF
$       ENDIF
$!
$       MRLOG_COUNT = MRLOG_COUNT + 1
$       IF MRLOG_COUNT .GT. 50
$       THEN
$               GOTO SFTP_PROCESS
$       ELSE
$               COPY/LOG 'MRLOG_FILE SFTP_TMP_DIR:'FILE_TMP
$               WRITE  SFTP_CTRL_FILE "put ''FILE_TMP'"
$               WRITE  RENAME_TMP_FILE "rename ''FILE_TMP' ''FILENAME'"
$               WRITE  DELETE_TMP_FILE "$DELETE/LOG XI_DAT:''FILENAME'"
$               GOTO MRLOG_FILE_COUNT
$       ENDIF
$!
$ SFTP_PROCESS:
$!
$       WRITE SYS$OUTPUT  "SFTP PROCESS FOR TRANSFER OF RSERC AND MRLOG FILES STARTED AT ''F$TIME()' "
$!
$       WRITE SFTP_CTRL_FILE   "exit"
$       WRITE RENAME_TMP_FILE  "exit"
$       CLOSE SFTP_CTRL_FILE
$       CLOSE RENAME_TMP_FILE
$       CLOSE DELETE_TMP_FILE
$!
$       create TAP_DAT_DIR:SFTP_ABS_IN_PROGRESS.FLAG
$!
$       SFTP      -b    TAP_DAT_DIR:SFTP_CTRL_FILE.DAT      "''destusername'@''desthostname'"
$!
$       IF .NOT. $STATUS
$       THEN
$               STATUS = "ERROR WHILE TRANSFERRING THE RSERCS AND MRLOG FILES FROM TAP TO ABS - SFTP PROCESS"
$               GOTO ERROR
$       ENDIF
$       DELETE/LOG TAP_DAT_DIR:SFTP_CTRL_FILE.DAT;*
$!
$       SFTP  -b  TAP_DAT_DIR:RENAME_SFTPD_FILES_TMP.COM  "''destusername'@''desthostname'"
$       IF .NOT. $STATUS
$       THEN
$             STATUS = "ERROR WHILE RENAMING THE RSERCS AND MRLOG FILES FROM .SFTP_TMP_RS TO .DAT IN ABS - SFTP PROCESS"
$             GOTO ERROR
$                               ENDIF
$       DELETE/LOG TAP_DAT_DIR:RENAME_SFTPD_FILES_TMP.COM;*
$       DELETE SFTP_TMP_DIR:*.*;*
$!
$       @TAP_DAT_DIR:DELETE_SFTPD_FILES_TMP.COM;
$       IF .NOT. $STATUS
$       THEN
$               STATUS = "ERROR WHILE DELETING SFTPD FILES FROM XI_DAT DIRECTORY"
$               GOTO ERROR
$       ENDIF
$       DELETE/LOG TAP_DAT_DIR:DELETE_SFTPD_FILES_TMP.COM;*
$!
$       DELETE/LOG TAP_DAT_DIR:SFTP_ABS_IN_PROGRESS.FLAG;*
$!
$       WRITE SYS$OUTPUT  "SFTP PROCESS FOR TRANSFER OF RSERC AND MRLOG FILES COMPLETED AT ''F$TIME()' "
$!
$ FINAL_CHECK:
$!
$       IF      (F$CVTIME() .GTS. F$TRNLNM("TAP_CLOSEDOWN_ALL")) .OR. (F$TRNLNM("RSERC_TRANS_SHUTDOWN") .EQS. "Y")
$       THEN
$               GOTO    EXIT
$       ELSE
$               GOTO MAIN_LOOP
$       ENDIF
$!
$!
$!=========================================================================================================
$!                      CLEAN FINISH
$!=========================================================================================================
$!
$ CLEAN_FINISH:
$!============
$!
$       PHASE   =       "CLEAN_FINISH"
$!
$       WRITE SYS$OUTPUT "''STATUS'"
$!
$       @TAP_COM_DIR:TAPLOG_MESS "   " "''PROCNAME'  HAS COMPLETED SUCCESSFULLY AT ''F$TIME()'" " "
$!
$       REQUEST/TO='OPERATOR'     "''PROCNAME' ''F$TIME()' : ''STATUS'  "
$!
$       GOTO    EXIT
$!
$!=========================================================================================================
$!                       RESTORE DCL ENVIRONMENT
$!=========================================================================================================
$!
$ EXIT:
$!====
$!
$       PHASE   =       "EXIT"
$!
$       SET MESSAGE 'messcodes'
$!
$       SET DEFAULT 'def_dir'
$!
$       EXIT
$!
$!=========================================================================================================
$!                      ERROR
$!=========================================================================================================
$!
$ ERROR:
$!=====
$!
$       PHASE   =       "ERROR"
$!
$       IF      STATUS .EQS. ""
$       THEN
$               STATUS          ==      $STATUS
$               ERROR_TEXT      =       F$MESSAGE('STATUS')
$       ELSE
$               ERROR_TEXT      =       STATUS
$       ENDIF
$!
$       WSO  "ERROR: *** ''ERROR_TEXT'"
$!
$       @TAP_COM_DIR:TAPLOG_MESS " ***" "''PROCNAME' - ''PHASE', ''ERROR_TEXT'" " "
$!
$       REQUEST/REPLY/TO='OPERATOR' "''PROCNAME' - ''PHASE', ''ERROR_TEXT' FAILED AT ''F$TIME()'"
$!
$       EXIT 4
$!
$!=========================================================================================================
$!                             ******** END OF PROGRAM *********
$!
