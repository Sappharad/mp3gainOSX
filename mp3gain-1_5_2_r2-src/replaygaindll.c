/*
 *  ReplayGainAnalysis DLL Wrapper - DLL Wrapper for Glen Sawyer's headers
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
 *  concept and filter values by David Robinson (David@Robinson.org)
 *    -- blame him if you think the idea is flawed
 *  coding by Glen Sawyer (mp3gain@hotmail.com) 735 W 255 N, Orem, UT 84057-4505 USA
 *    -- blame him if you think this runs too slowly, or the coding is otherwise flawed
 *  DLL Wrapper code for VC++5.0 by John Zitterkopf (zitt@bigfoot.com)
 *    -- blame him for nothing. This work evolves as needed.
 *
 *  For an explanation of the concepts and the basic algorithms involved, go to:
 *    http://www.replaygain.org/
 *
 *  V1.0 - jzitt
 *  * Based on V1.0 header source provided by Glen Sawyer
 *  * Attempts to maintain some backward capability with V0.9 of the same source.
 *
 *  V1.2.1 - jzitt 9/4/2002
 *  * Incorporates V1.2.1 MP3Gain sources.
 *  * Adds MP3GAIN capabilities to DLL. 
 */

/*define below tells sourcecode that we are compiling as a Win32 DLL*/
#ifndef asWIN32DLL
 #define asWIN32DLL  
#endif 

#include <windows.h>
#include "gain_analysis.h"
#include "mp3gain.h"
#include "rg_error.h" /*jzitt*/

#define MAXSAMPLES 2400


BOOL APIENTRY DllMain(HANDLE hModule,
					  unsigned long  dwReason,
                      LPVOID lpReserved)
{
	switch(dwReason)	{

		case DLL_PROCESS_ATTACH:
            mp3gainerrstr = NULL;
			break;

		case DLL_THREAD_ATTACH:

			break;

		case DLL_THREAD_DETACH:

			break;

		case DLL_PROCESS_DETACH:
            if (mp3gainerrstr != NULL) {
                free(mp3gainerrstr);
				mp3gainerrstr = NULL;
			}
			break;
	}

	return TRUE;
	UNREFERENCED_PARAMETER(lpReserved);
	UNREFERENCED_PARAMETER(hModule);
}


int AnalyzeSamplesInterleaved(char *samples, long num_samples, int
num_channels)
{

 double leftbuf[MAXSAMPLES], rightbuf[MAXSAMPLES];
 long i;
 long totSamples = num_samples;
 long nSamples   = num_samples;
 signed short int *samp = (signed short int *)samples;
 int  result = GAIN_ANALYSIS_ERROR;

/* NOTES:
 * leftbuf and rightbuf are arrays of doubles
 * samp is a short (16-bit) integer
 * inf is the input file
 * totSamples is the total number of samples remaining in the input file
 * MAXSAMPLES is the maximum number of samples to send to AnalyzeSamples at
once
 */

while (totSamples > 0)
{

 if (totSamples > MAXSAMPLES)
  nSamples = MAXSAMPLES;
 else
  nSamples = totSamples;

 if (num_channels == 2)
 {
  for (i = 0; i < nSamples; i++)
  {
   leftbuf[i] = *samp++; /* default conversion from short to double */
   rightbuf[i] = *samp++;
  }
  result = AnalyzeSamples(leftbuf,rightbuf,nSamples,2);
  if (result != GAIN_ANALYSIS_OK) return result;
 } //end stereo
 else
 { /* Just one channel (mono) */
  for (i = 0; i < nSamples; i++)
  {
   leftbuf[i] = *samp++;
  }
  result = AnalyzeSamples(leftbuf,NULL,nSamples,1);
  if (result != GAIN_ANALYSIS_OK) return result;
 } //end just mono

 totSamples -= nSamples;
} //end while

return result;

}


double GetRadioGain()
{
    return GetTitleGain();
}


double GetAudiophileGain()
{   
	return GetAlbumGain();
}

int InitGainAnalysisAsInt( int samplingFreq )
{
	return InitGainAnalysis( samplingFreq );
}

char *thFilename;
int thGainchange;

DWORD WINAPI changeGainThread( LPVOID lpParam )
{
	changeGain(thFilename, thGainchange, thGainchange);
	return 0;
	UNREFERENCED_PARAMETER(lpParam);
}

unsigned int __stdcall ChangeGainOfMP3File(char *filename, int gainchange)
{
	DWORD dwThreadID;
	HANDLE hThread;
	MSG msg;

    mp3gainerr = MP3GAIN_NOERROR;
	blnCancel = 0;
    if (mp3gainerrstr != NULL) {
        free(mp3gainerrstr);
		mp3gainerrstr = NULL;
	}
	thFilename = filename;
	thGainchange = gainchange;

	hThread = CreateThread(NULL,0,changeGainThread,NULL,0,&dwThreadID);
    
	if (hThread == NULL)
		return MP3GAIN_UNSPECIFED_ERROR;

    while ((MsgWaitForMultipleObjects(1, &hThread, 
			FALSE, INFINITE, QS_ALLINPUT)) == (WAIT_OBJECT_0 + 1))
	{
		while (PeekMessage(&msg, NULL, 0, 0, PM_REMOVE))
			DispatchMessage(&msg);
	}

    CloseHandle(hThread);
	return mp3gainerr;
}

unsigned int __stdcall GetMP3GainError()
{
	return mp3gainerr;
}

long __stdcall GetMP3GainErrorStrLen()
{
	if ((mp3gainerr == MP3GAIN_NOERROR) || (mp3gainerrstr == NULL))
		return 0;

	return strlen(mp3gainerrstr);
}

char * __stdcall GetMP3GainErrorStr( char * buffer, int buflen )
{
	if (buflen < 1) 
	{
		//strcpy(buffer,'\0');
		return NULL;//buffer;
	}

    if ((mp3gainerr == MP3GAIN_NOERROR) || (mp3gainerrstr == NULL)) {
        buffer[0] = '\0';
        return buffer;
    }

	buffer[buflen-1] = '\0'; //don't assume buffer has extra byte at the end
                            //for null terminator

	return strncpy( buffer, mp3gainerrstr, buflen-1 );
}

void __stdcall StopMP3GainProcessing()
{
	blnCancel = !0;
}

int __stdcall attachmsgpump(HANDLE ahwnd, UINT percentdonemsg, UINT errmsg)
{
	apphandle = 0;
	apppercentdonemsg = 0;
	apperrmsg = 0;
	if (ahwnd != 0) 
	{ 
		apphandle = ahwnd;
		apppercentdonemsg = percentdonemsg;
		apperrmsg = errmsg;
	}

	/*printf("Hi, John!\n"); 
	MessageBox( 0, "Hi, John!\n", "ReplayGainDLL\n", MB_OK ); */

	return(MP3GAIN_NOERROR); //return success
}

char * GetDLLVersion( char * buffer, int buflen )
{
	if (buflen < 1) 
	{
		//strcpy(buffer,'\0');
		return NULL;//buffer;
	}
	buffer[buflen] = '\0';

	return strncpy( buffer, MP3GAIN_VERSION, buflen-1 );
}