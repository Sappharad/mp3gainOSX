/*
 *  ReplayGainAnalysis Error Reporting 
 *     Handles error reporting for mp3gain in either standalone or DLL form.
 *
 *  Copyright (C) 2002 John Zitterkopf (zitt@bigfoot.com) 
 *                     (http://www.zittware.com)
 *
 *  These comments must remain intact in all copies of the source code.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2.1 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 *  based on code by Glen Sawyer (mp3gain@hotmail.com) 735 W 255 N, Orem, UT 84057-4505 USA
 *
 *  Error code for VC++5.0 by John Zitterkopf (zitt@bigfoot.com)
 *    -- blame him for nothing. This work evolves as needed.
 *
 *  V1.0 - jzitt
 *  * initial release based on V1.2.3 sources
 */

#include "rg_error.h"

#ifndef asWIN32DLL
extern int gSuccess;
#endif

void DoError( char * localerrstr, MMRESULT localerrnum )
{
#ifndef asWIN32DLL
    gSuccess = 0;
	fprintf(stdout, "%s", localerrstr);
#else
	//send message to DLL's parent
    mp3gainerr = localerrnum;
    if (mp3gainerrstr != NULL) {
        free(mp3gainerrstr);
		mp3gainerrstr = NULL;
	}
    mp3gainerrstr = malloc(strlen(localerrstr) + 1);
    strcpy(mp3gainerrstr,localerrstr);
	if  ( (apphandle != 0) && ( apperrmsg != 0 ) )
	{
		SendMessage(apphandle, apperrmsg, localerrnum, (LPARAM) localerrstr);
	}
#endif
}

void DoUnkError( char * localerrstr)
{
	DoError( localerrstr, MP3GAIN_UNSPECIFED_ERROR );
}

#ifdef asWIN32DLL
/*the sendpercentdone sends a windows message to the calling app with the progress 
  into the file (pdone). The calling app acknowledges the message by returning an 
  LRESULT. 
  LRESULT = 0 means continue processing the file.
  LRESULT != 0 means abort processing this file. 
*/
LRESULT sendpercentdone( int pdone, long filesize ) 
{  //send message to DLL's parent
	if ( (apphandle != 0)  && ( apppercentdonemsg != 0 ) )
	{
		return !(SendNotifyMessage(apphandle, apppercentdonemsg, pdone, filesize));
	}
	else return(0); //no calling app defined, send by 0 to continue
}
#endif
