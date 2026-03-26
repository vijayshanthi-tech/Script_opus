$!*****************************************************************************
$!
$       phase   =       "STARTING"
$!
$       on      warning then goto error
$!
$!*****************************************************************************
$!
$!
$! Procedure Name       :       TAP_JOB_STARTUP.COM
$! Case ID              :       TAPOP0190
$! Spec ID              :       TAPSO190.DOC
$!
$! Description          :       Generic TAP job startup
$!
$! Modified by          :       S.R.Campbell.   21-2-98         First draft.
$!                              S.R.Campbell.   3-6-98          Delete closedown
logical.
$!                                                              No informational
messages.
$!                              S.R.Campbell.   9-6-98          Delete closedown
logical
$!                                                              on failure as we
ll.
$!
$!
$!******************************************************************************
$!
$!              This defines my global symbols.
$!
$       verify          =       f$verify(0)
$       bell[0,32]      ==      %D7
$       crlf[0,8]       ==      %D13
$       crlf[8,8]       ==      %D10
$       csi[0,8]        ==      %D155
$       esc[0,8]        ==      %D27
$       tab[0,8]        ==      %D9
$!
$       big1    ==      "''esc'#3"
$       big2    ==      "''esc'#4"
$       blink   ==      "''csi'5m"
$       bold    ==      "''csi'1m"
$       cll     ==      "''csi'2K"
$       cls     ==      "''csi'2J"
$       grof    ==      "''esc'(B"
$       gron    ==      "''esc'(0"
$       l23     ==      "''csi'23;1H''cll'"
$       norm    ==      "''csi'?5l"
$       off     ==      "''csi'0m"
$       operator==      "oper8"
$       rev     ==      "''csi'7m"
$       rev_scr ==      "''csi'?5h"
$       status  ==      ""
$       top     ==      "''csi'1;1H"
$       under   ==      "''csi'4m"
$       wide    ==      "''esc'#6"
$       wo      ==      "write sys$output"
$       wof     ==      "write outfile"
$       verify  =       f$verify('verify')
$       input   ==      "$cel$system:cel$input"
$!
$!******************************************************************************
$!
$!
$!              SAVE CURRENT ENVIRONMENT
$!
$!
$ save_environment:
$!
$       phase           =       "SAVE_ENVIRONMENT"
$!
$       proc            =       f$environment("PROCEDURE")
$       procname        =       f$getjpi("","PRCNAM")
$!
$       set     on
$!
$       if      f$mode() .eqs. "INTERACTIVE"
$       then
$               set     term/nobroad
$               contcodes       =       f$environment("control")
$               messcodes       =       f$environment("message")
$               defdir          =       f$environment("default")
$               set     message/notext/noseverity/nofacility/noid
$               verify          =       f$verify(0)
$               set     control =       (t,y)
$       else
$               set     message/text/severity/facility/id
$               verify          =       f$verify(1)
$       endif
$!
$!
$!
$       if      p1 .eqs. "" .or. p2 .eqs. "" .or. p3 .eqs. ""
$       then
$               status  ==      "Parameter must be provided"
$               goto    error
$       endif
$!
$!
$!
$       set     noon
$       set     process/name="TAP_''p1'_''p2'"
$!
$!
$!
$       if      .not. $status
$       then
$               status  ==      "Process name cannot be set"
$               goto    error
$       endif
$!
$       set     on
$!
$       procname        =       "TAP_''p1'_''p2'"
$!
$!******************************************************************************
$!******************************************************************************
$!
$!              Main command procedure
$!
$ main:
$!
$       phase   =       "MAIN"
$!
$!
$!
$       if      f$search("tap_exe_dir:''p3'.exe") .eqs. ""
$       then
$               status  =       "''p3' unavailable"
$               goto    error
$       endif
$!
$       set     noon
$!
$       run     tap_exe_dir:'p3'
$!
$       status  ==      $status
$!
$!                      Now we can delete our own shutdown logical if it's there
$       mylog   =       f$process() + "_CLOSEDOWN"
$       if      f$trnlnm(mylog) .nes. "" then deassign/group &mylog
$!
$       if      .not. status
$       then
$               status  ==      "Error returned from program ''p3'"
$               goto    error
$       endif
$!
$!
$!
$       goto    exit
$!
$!
$!
$!******************************************************************************
$!******************************************************************************
$!
$!
$!                              GENERIC ERROR AND EXIT HANDLER
$!
$!
$ error:
$!
$       if      status .eqs. ""
$       then
$               status          ==      $status
$               error_text      =       f$message('status')
$       else
$               error_text      =       status
$       endif
$!
$       set     noon
$!
$       if      f$mode() .eqs. "INTERACTIVE"
$       then
$               wo      "''csi'20;1H''cls'''procname' - ''phase', ''error_text'"
$               read/prompt="''crlf'Please press ENTER to acknowledge error"  sy
s$command  status/end=error1
$           error1:
$       endif
$!
$!
$       @tap_com_dir:taplog_mess " ***" "''procname' - ''phase', ''error_text'"
" "
$!
$!
$       request/to='operator' "''procname' - ''phase', ''error_text'"
$!
$!
$!------------------------------------------------------------------------------
$!
$!
$!                              RESTORE DCL ENVIRONMENT
$!
$!
$ exit:
$!
$       phase   =       "EXIT"
$!
$       if      f$mode() .eqs. "INTERACTIVE"
$       then
$               status  ==      ""
$               wo      cls
$               set     term/broad
$               v       =  f$verify('verify')
$               set     message 'messcodes'
$               set     default 'defdir'
$               if      contcodes .nes ""  then set control  =  ('contcodes')
$       endif
$!
$       exit
$!
$!
$!******************************************************************************
$!******************************************************************************