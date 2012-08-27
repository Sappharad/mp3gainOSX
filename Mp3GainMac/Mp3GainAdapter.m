//
//  Mp3GainAdapter.m
//
//  Created by Paul Kratt on 7/9/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "Mp3GainAdapter.h"
#import "mp3gain.h"
#import "mpglib.h"
#import "gain_analysis.h"

/*
 *  mp3gain.c - analyzes mp3 files, determines the perceived volume, 
 *      and adjusts the volume of the mp3 accordingly
 *
 *  Copyright (C) 2001-2009 Glen Sawyer
 *  AAC support (C) 2004-2009 David Lasker, Altos Design, Inc.
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
 *  coding by Glen Sawyer (mp3gain@hotmail.com) 735 W 255 N, Orem, UT 84057-4505 USA
 *    -- go ahead and laugh at me for my lousy coding skillz, I can take it :)
 *       Just do me a favor and let me know how you improve the code.
 *       Thanks.
 *
 *  Unix-ification by Stefan Partheym¸ller
 *  (other people have made Unix-compatible alterations-- I just ended up using
 *   Stefan's because it involved the least re-work)
 *
 *  DLL-ification by John Zitterkopf (zitt@hotmail.com)
 *
 *  Additional tweaks by Artur Polaczynski, Mark Armbrust, and others
 */


/*
 *  General warning: I coded this in several stages over the course of several
 *  months. During that time, I changed my mind about my coding style and
 *  naming conventions many, many times. So there's not a lot of consistency
 *  in the code. Sorry about that. I may clean it up some day, but by the time
 *  I would be getting around to it, I'm sure that the more clever programmers
 *  out there will have come up with superior versions already...
 *
 *  So have fun dissecting.
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "apetag.h"
#include "id3tag.h"
#ifdef AACGAIN
#include "aacgain.h"
#endif

#ifndef WIN32
#undef asWIN32DLL
#ifdef __FreeBSD__
#include <sys/types.h>
#endif /* __FreeBSD__ */
#include <utime.h>
#endif /* WIN32 */

/* time stamp preservation when using temp file */
# include <sys/stat.h>
# include <utime.h>
# include <errno.h>
#define SWITCH_CHAR '-'

#include <fcntl.h>
#include <string.h>

/* I tweaked the mpglib library just a bit to spit out the raw
 * decoded double values, instead of rounding them to 16-bit integers.
 * Hence the "mpglibDBL" directory
 */

#ifndef asWIN32DLL
#include "interface.h"
#include "gain_analysis.h"
#endif

#include "mp3gain.h"  /*jzitt*/
#include "rg_error.h" /*jzitt*/

#define HEADERSIZE 4

#define CRC16_POLYNOMIAL        0x8005

#define BUFFERSIZE 3000000
#define WRITEBUFFERSIZE 100000

#define FULL_RECALC 1
#define AMP_RECALC 2
#define MIN_MAX_GAIN_RECALC 4

#ifdef AACGAIN
#define AACGAIN_ARG(x)  , x
#else
#define AACGAIN_ARG(x)
#endif

typedef struct {
	unsigned long fileposition;
	unsigned char val[2];
} wbuffer;

/* Yes, yes, I know I should do something about these globals */

wbuffer writebuffer[WRITEBUFFERSIZE];

unsigned long writebuffercnt;

unsigned char buffer[BUFFERSIZE];

int writeself = 0;
int QuietMode = 0;
int UsingTemp = 0;
int NowWriting = 0;
double lastfreq = -1.0;

int whichChannel = 0;
int BadLayer = 0;
int LayerSet = 0;
int Reckless = 0;
int wrapGain = 0;
int undoChanges = 0;

int skipTag = 0;
int deleteTag = 0;
int forceRecalculateTag = 0;
int checkTagOnly = 0;
static int useId3 = 0;

int gSuccess;

long inbuffer;
unsigned long bitidx;
unsigned char *wrdpntr;
unsigned char *curframe;

char *curfilename;

FILE *inf = NULL;

FILE *outf;

short int saveTime;

unsigned long filepos;

static const double bitrate[4][16] = {
	{ 1,  8, 16, 24, 32, 40, 48, 56,  64,  80,  96, 112, 128, 144, 160, 1 },
	{ 1,  1,  1,  1,  1,  1,  1,  1,   1,   1,   1,   1,   1,   1,   1, 1 },
	{ 1,  8, 16, 24, 32, 40, 48, 56,  64,  80,  96, 112, 128, 144, 160, 1 },
	{ 1, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 1 }
};
static const double frequency[4][4] = {
	{ 11.025, 12,  8,  1 },
	{      1,  1,  1,  1 },
	{  22.05, 24, 16,  1 },
	{   44.1, 48, 32,  1 }
};

long arrbytesinframe[16];

/* instead of writing each byte change, I buffer them up */
static
void flushWriteBuff() {
	unsigned long i;
	for (i = 0; i < writebuffercnt; i++) {
		fseek(inf,writebuffer[i].fileposition,SEEK_SET);
		fwrite(writebuffer[i].val,1,2,inf);
	}
	writebuffercnt = 0;
};



static
void addWriteBuff(unsigned long pos, unsigned char *vals) {
	if (writebuffercnt >= WRITEBUFFERSIZE) {
		flushWriteBuff();
		fseek(inf,filepos,SEEK_SET);
	}
	writebuffer[writebuffercnt].fileposition = pos;
	writebuffer[writebuffercnt].val[0] = *vals;
	writebuffer[writebuffercnt].val[1] = vals[1];
	writebuffercnt++;
	
};


/* fill the mp3 buffer */
static
unsigned long fillBuffer(long savelastbytes) {
	unsigned long i;
	unsigned long skip;
    unsigned long skipbuf;
    
	skip = 0;
	if (savelastbytes < 0) {
		skip = -savelastbytes;
		savelastbytes = 0;
	}
    
	if (UsingTemp && NowWriting) {
		if (fwrite(buffer,1,inbuffer-savelastbytes,outf) != (size_t)(inbuffer-savelastbytes))
            return 0;
	}
    
	if (savelastbytes != 0) /* save some of the bytes at the end of the buffer */
		memmove((void*)buffer,(const void*)(buffer+inbuffer-savelastbytes),savelastbytes);
	
	while (skip > 0) { /* skip some bytes from the input file */
        skipbuf = skip > BUFFERSIZE ? BUFFERSIZE : skip;
        
		i = (unsigned long)fread(buffer,1,skipbuf,inf);
        if (i != skipbuf)
            return 0;
        
		if (UsingTemp && NowWriting) {
			if (fwrite(buffer,1,skipbuf,outf) != skipbuf)
                return 0;
		}
		filepos += i;
        skip -= skipbuf;
	}
	i = (unsigned long)fread(buffer+savelastbytes,1,BUFFERSIZE-savelastbytes,inf);
    
	filepos = filepos + i;
	inbuffer = i + savelastbytes;
	return i;
}


static const unsigned char maskLeft8bits[8] = {
	0x00, 0x80, 0xC0, 0xE0, 0xF0, 0xF8, 0xFC, 0xFE };

static const unsigned char maskRight8bits[8] = {
	0xFF, 0x7F, 0x3F, 0x1F, 0x0F, 0x07, 0x03, 0x01 };

static void set8Bits(unsigned short val) {
    val <<= (8 - bitidx);
	wrdpntr[0] &= maskLeft8bits[bitidx];
	wrdpntr[0] |= (val  >> 8);
	wrdpntr[1] &= maskRight8bits[bitidx];
	wrdpntr[1] |= (val  & 0xFF);
	
	if (!UsingTemp) 
		addWriteBuff(filepos-(inbuffer-(wrdpntr-buffer)),wrdpntr);
}

static void skipBits(int nbits) {
    bitidx += nbits;
	wrdpntr += (bitidx >> 3);
	bitidx &= 7;
    
	return;
}



static unsigned char peek8Bits() {
	unsigned short rval;
    
	rval = wrdpntr[0];
	rval <<= 8;
	rval |= wrdpntr[1];
	rval >>= (8 - bitidx);
    
	return (rval & 0xFF);
}

static unsigned long skipID3v2() {
    /*
     *  An ID3v2 tag can be detected with the following pattern:
     *    $49 44 33 yy yy xx zz zz zz zz
     *  Where yy is less than $FF, xx is the 'flags' byte and zz is less than
     *  $80.
     */
	unsigned long ok;
	unsigned long ID3Size;
    
	ok = 1;
    
	if (wrdpntr[0] == 'I' && wrdpntr[1] == 'D' && wrdpntr[2] == '3' 
		&& wrdpntr[3] < 0xFF && wrdpntr[4] < 0xFF) {
        
		ID3Size = (long)(wrdpntr[9]) | ((long)(wrdpntr[8]) << 7) |
        ((long)(wrdpntr[7]) << 14) | ((long)(wrdpntr[6]) << 21);
        
		ID3Size += 10;
        
		wrdpntr = wrdpntr + ID3Size;
        
		if ((wrdpntr+HEADERSIZE-buffer) > inbuffer) {
			ok = fillBuffer(inbuffer-(wrdpntr-buffer));
			wrdpntr = buffer;
		}
	}
    
	return ok;
}

void passError(MMRESULT lerrnum, int numStrings, ...)
{
    char * errstr;
    size_t totalStrLen = 0;
    int i;
    va_list marker;
    
    va_start(marker, numStrings);
    for (i = 0; i < numStrings; i++) {
        totalStrLen += strlen(va_arg(marker, const char *));
    }
    va_end(marker);
    
    errstr = (char *)malloc(totalStrLen + 3);
    errstr[0] = '\0';
    
    va_start(marker, numStrings);
    for (i = 0; i < numStrings; i++) {
        strcat(errstr,va_arg(marker, const char *));
    }
    va_end(marker);
    
    NSAlert* alert = [NSAlert alertWithMessageText:NSLocalizedStringFromTable(@"MP3Gain_Error", @"ui_text", @"MP3Gain Error") defaultButton:NSLocalizedStringFromTable(@"OK", @"ui_text", @"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:[NSString stringWithCString:errstr encoding:NSASCIIStringEncoding]];
    [alert performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:TRUE];
    //DoError(errstr,lerrnum);
    free(errstr);
    errstr = NULL;
}

static unsigned long frameSearch(int startup) {
	unsigned long ok;
	int done;
    static int startfreq;
    static int startmpegver;
	long tempmpegver;
	double bitbase;
	int i;
    
	done = 0;
	ok = 1;
    
	if ((wrdpntr+HEADERSIZE-buffer) > inbuffer) {
		ok = fillBuffer(inbuffer-(wrdpntr-buffer));
		wrdpntr = buffer;
		if (!ok) done = 1;
	}
    
	while (!done) {
		
		done = 1;
        
		if ((wrdpntr[0] & 0xFF) != 0xFF)
			done = 0;       /* first 8 bits must be '1' */
		else if ((wrdpntr[1] & 0xE0) != 0xE0)
			done = 0;       /* next 3 bits are also '1' */
		else if ((wrdpntr[1] & 0x18) == 0x08)
			done = 0;       /* invalid MPEG version */
		else if ((wrdpntr[2] & 0xF0) == 0xF0)
			done = 0;       /* bad bitrate */
		else if ((wrdpntr[2] & 0xF0) == 0x00)
			done = 0;       /* we'll just completely ignore "free format" bitrates */
		else if ((wrdpntr[2] & 0x0C) == 0x0C)
			done = 0;       /* bad sample frequency */
		else if ((wrdpntr[1] & 0x06) != 0x02) { /* not Layer III */
			if (!LayerSet) {
				switch (wrdpntr[1] & 0x06) {
					case 0x06:
						BadLayer = !0;
						passError(MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                                  curfilename, " is an MPEG Layer I file, not a layer III file\n");
						return 0;
					case 0x04:
						BadLayer = !0;
						passError(MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                                  curfilename, " is an MPEG Layer II file, not a layer III file\n");
						return 0;
				}
			}
			done = 0; /* probably just corrupt data, keep trying */
		}
        else if (startup) {
            startmpegver = wrdpntr[1] & 0x18;
            startfreq = wrdpntr[2] & 0x0C;
			tempmpegver = startmpegver >> 3;
			if (tempmpegver == 3)
				bitbase = 1152.0;
			else
				bitbase = 576.0;
            
			for (i = 0; i < 16; i++)
				arrbytesinframe[i] = (long)(floor(floor((bitbase*bitrate[tempmpegver][i])/frequency[tempmpegver][startfreq >> 2]) / 8.0));
            
        }
        else { /* !startup -- if MPEG version or frequency is different, 
                then probably not correctly synched yet */
            if ((wrdpntr[1] & 0x18) != startmpegver)
                done = 0;
            else if ((wrdpntr[2] & 0x0C) != startfreq)
                done = 0;
            else if ((wrdpntr[2] & 0xF0) == 0) /* bitrate is "free format" probably just 
                                                corrupt data if we've already found 
                                                valid frames */
                done = 0;
        }
        
		if (!done) wrdpntr++;
        
		if ((wrdpntr+HEADERSIZE-buffer) > inbuffer) {
			ok = fillBuffer(inbuffer-(wrdpntr-buffer));
			wrdpntr = buffer;
			if (!ok) done = 1;
		}
	}
    
	if (ok) {
		if (inbuffer - (wrdpntr-buffer) < (arrbytesinframe[(wrdpntr[2] >> 4) & 0x0F] + ((wrdpntr[2] >> 1) & 0x01))) {
			ok = fillBuffer(inbuffer-(wrdpntr-buffer));
			wrdpntr = buffer;
		}
		bitidx = 0;
		curframe = wrdpntr;
	}
	return ok;
}


static int crcUpdate(int value, int crc)
{
    int i;
    value <<= 8;
    for (i = 0; i < 8; i++) {
		value <<= 1;
		crc <<= 1;
        
		if (((crc ^ value) & 0x10000))
			crc ^= CRC16_POLYNOMIAL;
	}
    return crc;
}


static void crcWriteHeader(int headerlength, char *header)
{
    int crc = 0xffff; /* (jo) init crc16 for error_protection */
    int i;
    
    crc = crcUpdate(((unsigned char*)header)[2], crc);
    crc = crcUpdate(((unsigned char*)header)[3], crc);
    for (i = 6; i < headerlength; i++) {
        crc = crcUpdate(((unsigned char*)header)[i], crc);
    }
    
    header[4] = crc >> 8;
    header[5] = crc & 255;
}


static long getSizeOfFile(char *filename)
{
    long size = 0;
    FILE *file;
    
    file = fopen(filename, "rb");
    if (file) {    
        fseek(file, 0, SEEK_END);
        size = ftell(file);
        fclose(file);
    }
    
    return size;
}


int deleteFile(char *filename)
{
    return remove(filename);
}

int moveFile(char *currentfilename, char *newfilename)
{
    return rename(currentfilename, newfilename);
}


/* Get File size and datetime stamp */
void fileTime(char *filename, timeAction action)
{
	static        int  timeSaved=0;
#ifdef WIN32
	HANDLE outfh;
	static FILETIME create_time, access_time, write_time;
#else
    static struct stat savedAttributes;
#endif
    
    if (action == storeTime) {
#ifdef WIN32
		outfh = CreateFile((LPCTSTR)filename,
                           GENERIC_READ,
                           FILE_SHARE_READ,
                           NULL,
                           OPEN_EXISTING,
                           FILE_ATTRIBUTE_NORMAL,
                           NULL);
		if (outfh != INVALID_HANDLE_VALUE) {
			if (GetFileTime(outfh,&create_time,&access_time,&write_time))
				timeSaved = !0;
            
			CloseHandle(outfh);
		}
#else
        timeSaved = (stat(filename, &savedAttributes) == 0);
#endif
    }
    else {
        if (timeSaved) {
#ifdef WIN32
			outfh = CreateFile((LPCTSTR)filename,
                               GENERIC_WRITE,
                               0,
                               NULL,
                               OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL,
                               NULL);
			if (outfh != INVALID_HANDLE_VALUE) {
				SetFileTime(outfh,&create_time,&access_time,&write_time);
				CloseHandle(outfh);
			}
#else
			struct utimbuf setTime;	
			
			setTime.actime = savedAttributes.st_atime;
			setTime.modtime = savedAttributes.st_mtime;
			timeSaved = 0;
            
			utime(filename, &setTime);
#endif
		}
    }      
}

unsigned long reportPercentWritten(unsigned long percent, unsigned long bytes)
{
    int ok = 1;
    
#ifndef asWIN32DLL
    fprintf(stderr,"                                                \r %2lu%% of %lu bytes written\r"
            ,percent,bytes);
    fflush(stderr);
#else
    /* report % back to calling app */
    ok = sendpercentdone( (int)percent, bytes ); 
    //non-zero return means error bail out
    if ( ok != 0)
	    return 0;
    ok = 1; /* allow us to continue processing file */
#endif
    
    return ok;
}

int numFiles, totFiles;
unsigned long reportPercentAnalyzed(unsigned long percent, unsigned long bytes)
{
	char fileDivFiles[21];
    fileDivFiles[0]='\0';
    
    if (totFiles-1)	/* if 1 file then don't show [x/n] */
	    sprintf(fileDivFiles,"[%d/%d]",numFiles,totFiles);
    
	fprintf(stderr,"                                           \r%s %2lu%% of %lu bytes analyzed\r"
            ,fileDivFiles,percent,bytes);
	fflush(stderr);
    return 1;
}

void scanFrameGain() {
	int crcflag;
	int mpegver;
	int mode;
	int nchan;
	int gr, ch;
	int gain;
    
	mpegver = (curframe[1] >> 3) & 0x03;
	crcflag = curframe[1] & 0x01;
	mode = (curframe[3] >> 6) & 0x03;
	nchan = (mode == 3) ? 1 : 2;
    
	if (!crcflag)
		wrdpntr = curframe + 6;
	else
		wrdpntr = curframe + 4;
    
	bitidx = 0;
    
	if (mpegver == 3) { /* 9 bit main_data_begin */
		wrdpntr++;
		bitidx = 1;
        
		if (mode == 3)
			skipBits(5); /* private bits */
		else
			skipBits(3); /* private bits */
        
		skipBits(nchan * 4);  /* scfsi[ch][band] */
		for (gr = 0; gr < 2; gr++) {
			for (ch = 0; ch < nchan; ch++) {
				skipBits(21);
				gain = peek8Bits();
				if (*minGain > gain) {
					*minGain = gain;
				}
				if (*maxGain < gain) {
					*maxGain = gain;
				}
				skipBits(38);
			}
		}
	} else { /* mpegver != 3 */
		wrdpntr++; /* 8 bit main_data_begin */
        
		if (mode == 3)
			skipBits(1);
		else
			skipBits(2);
        
		/* only one granule, so no loop */
		for (ch = 0; ch < nchan; ch++) {
			skipBits(21);
			gain = peek8Bits();
			if (*minGain > gain) {
				*minGain = gain;
			}
			if (*maxGain < gain) {
				*maxGain = gain;
			}
			skipBits(42);
		}
	}
}

static int changeGain(char *filename AACGAIN_ARG(AACGainHandle aacH), int leftgainchange, int rightgainchange) {
    unsigned long ok;
    int mode;
    int crcflag;
    unsigned char *Xingcheck;
    unsigned long frame;
    int nchan;
    int ch;
    int gr;
    unsigned char gain;
    int bitridx;
    int freqidx;
    long bytesinframe;
    int sideinfo_len;
    int mpegver;
    long gFilesize = 0;
    char *outfilename;
    int gainchange[2];
    int singlechannel;
    long outlength, inlength; /* size checker when using Temp files */
    
    outfilename = NULL;
    frame = 0;
    BadLayer = 0;
    LayerSet = Reckless;
    
    NowWriting = !0;
    
    if ((leftgainchange == 0) && (rightgainchange == 0))
        return 0;
    
#ifdef AACGAIN
    if (aacH)
    {
        int rc = aac_modify_gain(aacH, leftgainchange, rightgainchange, 
                                 QuietMode ? NULL : reportPercentWritten);
        NowWriting = 0;
        if (rc)
            passError(MP3GAIN_FILEFORMAT_NOTSUPPORTED, 1, "failed to modify gain\n");
        return rc;
    }
#endif
    
    gainchange[0] = leftgainchange;
    gainchange[1] = rightgainchange;
    singlechannel = !(leftgainchange == rightgainchange);
    
    if (saveTime)
        fileTime(filename, storeTime);
    
    gFilesize = getSizeOfFile(filename);
    
    if (UsingTemp) {
        fflush(stderr);
        fflush(stdout);
        outlength = (long)strlen(filename);
        outfilename = (char *)malloc(outlength+5);
        strcpy(outfilename,filename);
        if ((filename[outlength-3] == 'T' || filename[outlength-3] == 't') &&
 			(filename[outlength-2] == 'M' || filename[outlength-2] == 'm') &&
 			(filename[outlength-1] == 'P' || filename[outlength-1] == 'p')) {
            strcat(outfilename,".TMP");
        }
        else {
            outfilename[outlength-3] = 'T';
            outfilename[outlength-2] = 'M';
            outfilename[outlength-1] = 'P';
        }
        
        inf = fopen(filename,"r+b");
        
        if (inf != NULL) {
            outf = fopen(outfilename, "wb");
            
            if (outf == NULL) {
		        fclose(inf); 
                inf = NULL;
                passError(MP3GAIN_UNSPECIFED_ERROR, 3,
                          "\nCan't open ", outfilename, " for temp writing\n");
                return M3G_ERR_CANT_MAKE_TMP;
            } 
            
        }
    }
    else {
        inf = fopen(filename,"r+b");
    }
    
    if (inf == NULL) {
        if (UsingTemp && (outf != NULL))
            fclose(outf);
        passError( MP3GAIN_UNSPECIFED_ERROR, 3,
                  "\nCan't open ", filename, " for modifying\n");
        return M3G_ERR_CANT_MODIFY_FILE;
    }
    else {
        writebuffercnt = 0;
        inbuffer = 0;
        filepos = 0;
        bitidx = 0;
        ok = fillBuffer(0);
        if (ok) {
            
            wrdpntr = buffer;
            
            ok = skipID3v2();
            
            ok = frameSearch(!0);
            if (!ok) {
                if (!BadLayer)
                    passError( MP3GAIN_UNSPECIFED_ERROR, 3,
                              "Can't find any valid MP3 frames in file ", filename, "\n");
            }
            else {
                LayerSet = 1; /* We've found at least one valid layer 3 frame.
                               * Assume any later layer 1 or 2 frames are just
                               * bitstream corruption
                               */
                mode = (curframe[3] >> 6) & 3;
                
                if ((curframe[1] & 0x08) == 0x08) /* MPEG 1 */
                    sideinfo_len = (mode == 3) ? 4 + 17 : 4 + 32;
                else                /* MPEG 2 */
                    sideinfo_len = (mode == 3) ? 4 + 9 : 4 + 17;
                
                if (!(curframe[1] & 0x01))
                    sideinfo_len += 2;
                
                Xingcheck = curframe + sideinfo_len;
                
                //LAME CBR files have "Info" tags, not "Xing" tags
                if ((Xingcheck[0] == 'X' && Xingcheck[1] == 'i' && Xingcheck[2] == 'n' && Xingcheck[3] == 'g') ||
					(Xingcheck[0] == 'I' && Xingcheck[1] == 'n' && Xingcheck[2] == 'f' && Xingcheck[3] == 'o')) {
                    bitridx = (curframe[2] >> 4) & 0x0F;
                    if (bitridx == 0) {
                        passError( MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                                  filename, " is free format (not currently supported)\n");
                        ok = 0;
                    }
                    else {
                        mpegver = (curframe[1] >> 3) & 0x03;
                        freqidx = (curframe[2] >> 2) & 0x03;
                        
                        bytesinframe = arrbytesinframe[bitridx] + ((curframe[2] >> 1) & 0x01);
                        
                        wrdpntr = curframe + bytesinframe;
                        
                        ok = frameSearch(0);
                    }
                }
                
                frame = 1;
            } /* if (!ok) else */
            
            while (ok) {
                bitridx = (curframe[2] >> 4) & 0x0F;
                if (singlechannel) {
                    if ((curframe[3] >> 6) & 0x01) { /* if mode is NOT stereo or dual channel */
                        passError( MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                                  filename, ": Can't adjust single channel for mono or joint stereo\n");
                        ok = 0;
                    }
                }
                if (bitridx == 0) {
                    passError( MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                              filename, " is free format (not currently supported)\n");
                    ok = 0;
                }
                if (ok) {
                    mpegver = (curframe[1] >> 3) & 0x03;
                    crcflag = curframe[1] & 0x01;
                    freqidx = (curframe[2] >> 2) & 0x03;
                    
                    bytesinframe = arrbytesinframe[bitridx] + ((curframe[2] >> 1) & 0x01);
                    mode = (curframe[3] >> 6) & 0x03;
                    nchan = (mode == 3) ? 1 : 2;
                    
                    if (!crcflag) /* we DO have a crc field */
                        wrdpntr = curframe + 6; /* 4-byte header, 2-byte CRC */
                    else
                        wrdpntr = curframe + 4; /* 4-byte header */
                    
                    bitidx = 0;
                    
                    if (mpegver == 3) { /* 9 bit main_data_begin */
                        wrdpntr++;
                        bitidx = 1;
                        
                        if (mode == 3)
                            skipBits(5); /* private bits */
                        else
                            skipBits(3); /* private bits */
                        
                        skipBits(nchan*4); /* scfsi[ch][band] */
                        for (gr = 0; gr < 2; gr++)
                            for (ch = 0; ch < nchan; ch++) {
                                skipBits(21);
                                gain = peek8Bits();
                                if (wrapGain)
                                    gain += (unsigned char)(gainchange[ch]);
                                else {
                                    if (gain != 0) {
                                        if ((int)(gain) + gainchange[ch] > 255)
                                            gain = 255;
                                        else if ((int)gain + gainchange[ch] < 0)
                                            gain = 0;
                                        else
                                            gain += (unsigned char)(gainchange[ch]);
                                    }
                                }
                                set8Bits(gain);
                                skipBits(38);
                            }
                        if (!crcflag) {
                            if (nchan == 1)
                                crcWriteHeader(23,(char*)curframe);
                            else
                                crcWriteHeader(38,(char*)curframe);
                            /* WRITETOFILE */
                            if (!UsingTemp) 
                                addWriteBuff(filepos-(inbuffer-(curframe+4-buffer)),curframe+4);
                        }
                    }
                    else { /* mpegver != 3 */
                        wrdpntr++; /* 8 bit main_data_begin */
                        
                        if (mode == 3)
                            skipBits(1);
                        else
                            skipBits(2);
                        
                        /* only one granule, so no loop */
                        for (ch = 0; ch < nchan; ch++) {
                            skipBits(21);
                            gain = peek8Bits();
                            if (wrapGain)
                                gain += (unsigned char)(gainchange[ch]);
                            else {
                                if (gain != 0) {
                                    if ((int)(gain) + gainchange[ch] > 255)
                                        gain = 255;
                                    else if ((int)gain + gainchange[ch] < 0)
                                        gain = 0;
                                    else
                                        gain += (unsigned char)(gainchange[ch]);
                                }
                            }
                            set8Bits(gain);
                            skipBits(42);
                        }
                        if (!crcflag) {
                            if (nchan == 1)
                                crcWriteHeader(15,(char*)curframe);
                            else
                                crcWriteHeader(23,(char*)curframe);
                            /* WRITETOFILE */
                            if (!UsingTemp) 
                                addWriteBuff(filepos-(inbuffer-(curframe+4-buffer)),curframe+4);
                        }
                        
                    }
                    if (!QuietMode) 
                    {
                        frame++;
                        if (frame%200 == 0) {
                            ok = reportPercentWritten((unsigned long)(((double)(filepos-(inbuffer-(curframe+bytesinframe-buffer))) * 100.0) / gFilesize),gFilesize);
                            if (!ok)
                                return ok;
                        }
                    }
                    wrdpntr = curframe+bytesinframe;
                    ok = frameSearch(0);
                }
            }
        }
        
#ifdef asWIN32DLL
        if (blnCancel) { //need to clean up as best as possible
            fclose(inf);
            if (UsingTemp) {
                fclose(outf);
                deleteFile(outfilename);
                free(outfilename);
                passError(MP3GAIN_CANCELLED,2,"Cancelled processing of ",filename);
            }
            else {
                passError(MP3GAIN_CANCELLED,3,"Cancelled processing.\n", filename, " is probably corrupted now.");
            }
            if (saveTime) 
                fileTime(filename, setStoredTime);		
            return;
        }
#endif
        
        if (!QuietMode) {
#ifndef asWIN32DLL
            fprintf(stderr,"                                                   \r");
#else
            /* report DONE (100%) message back to calling app */
            sendpercentdone( 100, gFilesize );
#endif
        }
        fflush(stderr);
        fflush(stdout);
        if (UsingTemp) {
            while (fillBuffer(0));
            fflush(outf);
#ifdef WIN32
            outlength = _filelength(_fileno(outf));
            inlength = _filelength(_fileno(inf));
#else
            fseek(outf, 0, SEEK_END);
            fseek(inf, 0, SEEK_END);
            outlength=ftell(outf);
            inlength =ftell(inf); 
#endif
#ifdef __BEOS__
            /* some stuff to preserve attributes */
            do {
                DIR *attrs = NULL;
                struct dirent *de;
                struct attr_info ai;
                int infd, outfd;
                void *attrdata;
                
                infd = fileno(inf);
                if (infd < 0)
                    goto attrerror;
                outfd = fileno(outf);
                if (outfd < 0)
                    goto attrerror;
                attrs = fs_fopen_attr_dir(infd);
                while ((de = fs_read_attr_dir(attrs)) != NULL) {
                    if (fs_stat_attr(infd, de->d_name, &ai) < B_OK)
                        goto attrerror;
                    if ((attrdata = malloc(ai.size)) == NULL)
                        goto attrerror;
                    fs_read_attr(infd, de->d_name, ai.type, 0, attrdata, ai.size);
                    fs_write_attr(outfd, de->d_name, ai.type, 0, attrdata, ai.size);
                    free(attrdata);
                }
                fs_close_attr_dir(attrs);
                break;
            attrerror:
                if (attrdata)
                    free(attrdata);
                if (attrs)
                    fs_close_attr_dir(attrs);
                fprintf(stderr, "can't preserve attributes for '%s': %s\n", filename, strerror(errno));
            } while (0);
#endif
            fclose(outf);
            fclose(inf);
            inf = NULL;
            
            if (outlength != inlength) {
                deleteFile(outfilename);
                passError( MP3GAIN_UNSPECIFED_ERROR, 3,
                          "Not enough temp space on disk to modify ", filename, 
                          "\nEither free some space, or do not use \"temp file\" option\n");
                return M3G_ERR_NOT_ENOUGH_TMP_SPACE;
            }
            else {
                
                if (deleteFile(filename)) {
                    deleteFile(outfilename); //try to delete tmp file
                    passError( MP3GAIN_UNSPECIFED_ERROR, 3,
                              "Can't open ", filename, " for modifying\n");
                    return M3G_ERR_CANT_MODIFY_FILE;
                }
                if (moveFile(outfilename, filename)) {
                    passError( MP3GAIN_UNSPECIFED_ERROR, 9,
                              "Problem re-naming ", outfilename, " to ", filename, 
                              "\nThe mp3 was correctly modified, but you will need to re-name ", 
                              outfilename, " to ", filename, 
                              " yourself.\n");
                    return M3G_ERR_RENAME_TMP;
                };
                if (saveTime)
                    fileTime(filename, setStoredTime);
            }
            free(outfilename);
        }
        else {
            flushWriteBuff();
            fclose(inf);
            inf = NULL;
            if (saveTime) 
                fileTime(filename, setStoredTime);		
        }
    }
    
    NowWriting = 0;
    
    return 0;
}


#ifndef asWIN32DLL

#ifdef AACGAIN
void WriteAacGainTags (AACGainHandle aacH, struct MP3GainTagInfo *info) {
    if (info->haveAlbumGain)
        aac_set_tag_float(aacH, replaygain_album_gain, info->albumGain);
    if (info->haveAlbumPeak)
        aac_set_tag_float(aacH, replaygain_album_peak, info->albumPeak);
    if (info->haveAlbumMinMaxGain)
        aac_set_tag_int_2(aacH, replaygain_album_minmax, info->albumMinGain, info->albumMaxGain);
    if (info->haveTrackGain)
        aac_set_tag_float(aacH, replaygain_track_gain, info->trackGain);
    if (info->haveTrackPeak)
        aac_set_tag_float(aacH, replaygain_track_peak, info->trackPeak);
    if (info->haveMinMaxGain)
        aac_set_tag_int_2(aacH, replaygain_track_minmax, info->minGain, info->maxGain);
    if (info->haveUndo)
        aac_set_tag_int_2(aacH, replaygain_undo, info->undoLeft, info->undoRight);
}
#endif


static void WriteMP3GainTag(char *filename AACGAIN_ARG(AACGainHandle aacH), struct MP3GainTagInfo *info, struct FileTagsStruct *fileTags, int saveTimeStamp)
{
#ifdef AACGAIN
    if (aacH) {
        WriteAacGainTags(aacH, info);
    } else
#endif
        if (useId3) {
            /* Write ID3 tag; remove stale APE tag if it exists. */
            if (WriteMP3GainID3Tag(filename, info, saveTimeStamp) >= 0)
                RemoveMP3GainAPETag(filename, saveTimeStamp);
        } else {
            /* Write APE tag */
            WriteMP3GainAPETag(filename, info, fileTags, saveTimeStamp);
        }
}


void changeGainAndTag(char *filename AACGAIN_ARG(AACGainHandle aacH), int leftgainchange, int rightgainchange, struct MP3GainTagInfo *tag, struct FileTagsStruct *fileTag) {
    double dblGainChange;
    int curMin;
    int curMax;
    
    if (leftgainchange != 0 || rightgainchange != 0) {
        if (!changeGain(filename AACGAIN_ARG(aacH), leftgainchange, rightgainchange)) {
            if (!tag->haveUndo) {
                tag->undoLeft = 0;
                tag->undoRight = 0;
            }
            tag->dirty = !0;
            tag->undoRight -= rightgainchange;
            tag->undoLeft -= leftgainchange;
            tag->undoWrap = wrapGain;
            
            /* if undo == 0, then remove Undo tag */
            tag->haveUndo = !0;
            /* on second thought, don't remove it. Shortening the tag causes full file copy, which is slow so we avoid it if we can
             tag->haveUndo = 
             ((tag->undoRight != 0) || 
             (tag->undoLeft != 0));
             */
            
            if (leftgainchange == rightgainchange) { /* don't screw around with other fields if mis-matched left/right */
                dblGainChange = leftgainchange * 1.505; /* approx. 5 * log10(2) */
                if (tag->haveTrackGain) {
                    tag->trackGain -= dblGainChange;
                }
                if (tag->haveTrackPeak) {
                    tag->trackPeak *= pow(2.0,(double)(leftgainchange)/4.0);
                }
                if (tag->haveAlbumGain) {
                    tag->albumGain -= dblGainChange;
                }
                if (tag->haveAlbumPeak) {
                    tag->albumPeak *= pow(2.0,(double)(leftgainchange)/4.0);
                }
                if (tag->haveMinMaxGain) {
                    curMin = tag->minGain;
                    curMax = tag->maxGain;
                    curMin += leftgainchange;
                    curMax += leftgainchange;
                    if (wrapGain) {
                        if (curMin < 0 || curMin > 255 || curMax < 0 || curMax > 255) {
                            /* we've lost the "real" min or max because of wrapping */
                            tag->haveMinMaxGain = 0;
                        }
                    } else {
                        tag->minGain = tag->minGain == 0 ? 0 : curMin < 0 ? 0 : curMin > 255 ? 255 : curMin;
                        tag->maxGain = curMax < 0 ? 0 : curMax > 255 ? 255 : curMax;
                    }
                }
                if (tag->haveAlbumMinMaxGain) {
                    curMin = tag->albumMinGain;
                    curMax = tag->albumMaxGain;
                    curMin += leftgainchange;
                    curMax += leftgainchange;
                    if (wrapGain) {
                        if (curMin < 0 || curMin > 255 || curMax < 0 || curMax > 255) {
                            /* we've lost the "real" min or max because of wrapping */
                            tag->haveAlbumMinMaxGain = 0;
                        }
                    } else {
                        tag->albumMinGain = tag->albumMinGain == 0 ? 0 : curMin < 0 ? 0 : curMin > 255 ? 255 : curMin;
                        tag->albumMaxGain = curMax < 0 ? 0 : curMax > 255 ? 255 : curMax;
                    }
                }
            } // if (leftgainchange == rightgainchange ...
            WriteMP3GainTag(filename AACGAIN_ARG(aacH), tag, fileTag, saveTime);
        } // if (!changeGain(filename ...
    }// if (leftgainchange !=0 ...
    
}

static int queryUserForClipping(char * argv_mainloop,int intGainChange)
{
    /*char ch;
    
    fprintf(stderr,"\nWARNING: %s may clip with mp3 gain change %d\n",argv_mainloop,intGainChange);
    ch = 0;
    fflush(stdout);
    fflush(stderr);
    while ((ch != 'Y') && (ch != 'N')) {
        fprintf(stderr,"Make change? [y/n]:");
        fflush(stderr);
        ch = getchar();
        ch = toupper(ch);
    }
    if (ch == 'N')
        return 0;*/
    
    return 1;
}

static void showVersion(char *progname) {
#ifdef AACGAIN
    fprintf(stderr,"aacgain version %s, derived from mp3gain version %s\n",AACGAIN_VERSION,MP3GAIN_VERSION);
#else
    fprintf(stderr,"%s version %s\n",progname,MP3GAIN_VERSION);
#endif
}


static void wrapExplanation() {
    fprintf(stderr,"Here's the problem:\n");
    fprintf(stderr,"The \"global gain\" field that mp3gain adjusts is an 8-bit unsigned integer, so\n");
    fprintf(stderr,"the possible values are 0 to 255.\n");
    fprintf(stderr,"\n");
    fprintf(stderr,"MOST mp3 files (in fact, ALL the mp3 files I've examined so far) don't go\n");
    fprintf(stderr,"over 230. So there's plenty of headroom on top-- you can increase the gain\n");
    fprintf(stderr,"by 37dB (multiplying the amplitude by 76) without a problem.\n");
    fprintf(stderr,"\n");
    fprintf(stderr,"The problem is at the bottom of the range. Some encoders create frames with\n");
    fprintf(stderr,"0 as the global gain for silent frames.\n");
    fprintf(stderr,"What happens when you _lower_ the global gain by 1?\n");
    fprintf(stderr,"Well, in the past, mp3gain always simply wrapped the result up to 255.\n");
    fprintf(stderr,"That way, if you lowered the gain by any amount and then raised it by the\n");
    fprintf(stderr,"same amount, the mp3 would always be _exactly_ the same.\n");
    fprintf(stderr,"\n");
    fprintf(stderr,"There are a few encoders out there, unfortunately, that create 0-gain frames\n");
    fprintf(stderr,"with other audio data in the frame.\n");
    fprintf(stderr,"As long as the global gain is 0, you'll never hear the data.\n");
    fprintf(stderr,"But if you lower the gain on such a file, the global gain is suddenly _huge_.\n");
    fprintf(stderr,"If you play this modified file, there might be a brief, very loud blip.\n");
    fprintf(stderr,"\n");
    fprintf(stderr,"So now the default behavior of mp3gain is to _not_ wrap gain changes.\n");
    fprintf(stderr,"In other words,\n");
    fprintf(stderr,"1) If the gain change would make a frame's global gain drop below 0,\n");
    fprintf(stderr,"   then the global gain is set to 0.\n");
    fprintf(stderr,"2) If the gain change would make a frame's global gain grow above 255,\n");
    fprintf(stderr,"   then the global gain is set to 255.\n");
    fprintf(stderr,"3) If a frame's global gain field is already 0, it is not changed, even if\n");
    fprintf(stderr,"   the gain change is a positive number\n");
    fprintf(stderr,"\n");
    fprintf(stderr,"To use the original \"wrapping\" behavior, use the \"%cw\" switch.\n",SWITCH_CHAR);
#ifdef AACGAIN
    fprintf(stderr,"\n");
    fprintf(stderr,"The \"%cw\" switch is not supported for AAC files. An attempt to wrap\n",SWITCH_CHAR);
    fprintf(stderr,"an AAC file is treated as an error, and the file will not be modified.\n");
#endif
    exit(0);
    
}


static void errUsage(char *progname) {
    showVersion(progname);
    fprintf(stderr,"copyright(c) 2001-2009 by Glen Sawyer\n");
#ifdef AACGAIN
    fprintf(stderr,"AAC support copyright(c) 2004-2009 David Lasker, Altos Design, Inc.\n");
#endif
    fprintf(stderr,"uses mpglib, which can be found at http://www.mpg123.de\n");
#ifdef AACGAIN
    fprintf(stderr,"AAC support uses faad2 (http://www.audiocoding.com), and\n");
    fprintf(stderr,"mpeg4ip's mp4v2 (http://www.mpeg4ip.net)\n");
#endif
    fprintf(stderr,"Usage: %s [options] <infile> [<infile 2> ...]\n",progname);
    fprintf(stderr,"  --use %c? or %ch for a full list of options\n",SWITCH_CHAR,SWITCH_CHAR);
    fclose(stdout);
    fclose(stderr);
    exit(1);
}


static void fullUsage(char *progname) {
    showVersion(progname);
    fprintf(stderr,"copyright(c) 2001-2009 by Glen Sawyer\n");
#ifdef AACGAIN
    fprintf(stderr,"AAC support copyright(c) 2004-2009 David Lasker, Altos Design, Inc.\n");
#endif
    fprintf(stderr,"uses mpglib, which can be found at http://www.mpg123.de\n");
#ifdef AACGAIN
    fprintf(stderr,"AAC support uses faad2 (http://www.audiocoding.com), and\n");
    fprintf(stderr,"mpeg4ip's mp4v2 (http://www.mpeg4ip.net)\n");
#endif
    fprintf(stderr,"Usage: %s [options] <infile> [<infile 2> ...]\n",progname);
    fprintf(stderr,"options:\n");
    fprintf(stderr,"\t%cv - show version number\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cg <i>  - apply gain i without doing any analysis\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cl 0 <i> - apply gain i to channel 0 (left channel)\n",SWITCH_CHAR);
    fprintf(stderr,"\t          without doing any analysis (ONLY works for STEREO files,\n");
    fprintf(stderr,"\t          not Joint Stereo)\n");
    fprintf(stderr,"\t%cl 1 <i> - apply gain i to channel 1 (right channel)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%ce - skip Album analysis, even if multiple files listed\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cr - apply Track gain automatically (all files set to equal loudness)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%ck - automatically lower Track/Album gain to not clip audio\n",SWITCH_CHAR);
    fprintf(stderr,"\t%ca - apply Album gain automatically (files are all from the same\n",SWITCH_CHAR);
    fprintf(stderr,"\t              album: a single gain change is applied to all files, so\n");
    fprintf(stderr,"\t              their loudness relative to each other remains unchanged,\n");
    fprintf(stderr,"\t              but the average album loudness is normalized)\n");
    fprintf(stderr,"\t%cm <i> - modify suggested MP3 gain by integer i\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cd <n> - modify suggested dB gain by floating-point n\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cc - ignore clipping warning when applying gain\n",SWITCH_CHAR);
    fprintf(stderr,"\t%co - output is a database-friendly tab-delimited list\n",SWITCH_CHAR);
    fprintf(stderr,"\t%ct - writes modified data to temp file, then deletes original\n",SWITCH_CHAR);
    fprintf(stderr,"\t     instead of modifying bytes in original file\n");
#ifdef AACGAIN
    fprintf(stderr,"\t     A temp file is always used for AAC files.\n");
#endif
    fprintf(stderr,"\t%cq - Quiet mode: no status messages\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cp - Preserve original file timestamp\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cx - Only find max. amplitude of file\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cf - Assume input file is an MPEG 2 Layer III file\n",SWITCH_CHAR);
    fprintf(stderr,"\t     (i.e. don't check for mis-named Layer I or Layer II files)\n");
#ifdef AACGAIN
    fprintf(stderr,"\t      This option is ignored for AAC files.\n");
#endif
    fprintf(stderr,"\t%c? or %ch - show this message\n",SWITCH_CHAR,SWITCH_CHAR);
    fprintf(stderr,"\t%cs c - only check stored tag info (no other processing)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cs d - delete stored tag info (no other processing)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cs s - skip (ignore) stored tag info (do not read or write tags)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cs r - force re-calculation (do not read tag info)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cs i - use ID3v2 tag for MP3 gain info\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cs a - use APE tag for MP3 gain info (default)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cu - undo changes made (based on stored tag info)\n",SWITCH_CHAR);
    fprintf(stderr,"\t%cw - \"wrap\" gain change if gain+change > 255 or gain+change < 0\n",SWITCH_CHAR);
#ifdef AACGAIN
    fprintf(stderr,"\t      MP3 only. (use \"%c? wrap\" switch for a complete explanation)\n",SWITCH_CHAR);
#else
    fprintf(stderr,"\t      (use \"%c? wrap\" switch for a complete explanation)\n",SWITCH_CHAR);
#endif
    fprintf(stderr,"If you specify %cr and %ca, only the second one will work\n",SWITCH_CHAR,SWITCH_CHAR);
    fprintf(stderr,"If you do not specify %cc, the program will stop and ask before\n     applying gain change to a file that might clip\n",SWITCH_CHAR);
    fclose(stdout);
    fclose(stderr);
    exit(0);
}

#ifdef AACGAIN
void ReadAacTags(AACGainHandle gh, struct MP3GainTagInfo *info)
{
    int p1, p2;
    
    if (aac_get_tag_float(gh, replaygain_album_gain, &info->albumGain) == 0)
        info->haveAlbumGain = !0;
    if (aac_get_tag_float(gh, replaygain_album_peak, &info->albumPeak) == 0)
        info->haveAlbumPeak = !0;
    if (aac_get_tag_int_2(gh, replaygain_album_minmax, &p1, &p2) == 0)
    {
        info->albumMinGain = p1;
        info->albumMaxGain = p2;
        info->haveAlbumMinMaxGain = !0;
    }
    if (aac_get_tag_float(gh, replaygain_track_gain, &info->trackGain) == 0)
        info->haveTrackGain = !0;
    if (aac_get_tag_float(gh, replaygain_track_peak, &info->trackPeak) == 0)
        info->haveTrackPeak = !0;
    if (aac_get_tag_int_2(gh, replaygain_track_minmax, &p1, &p2) == 0)
    {
        info->minGain = p1;
        info->maxGain = p2;
        info->haveMinMaxGain = !0;
    }
    if (aac_get_tag_int_2(gh, replaygain_undo, &p1, &p2) == 0)
    {
        info->undoLeft = p1;
        info->undoRight = p2;
        info->haveUndo = !0;
    }
}
#endif

void dumpTaginfo(struct MP3GainTagInfo *info) {
    fprintf(stderr, "haveAlbumGain       %d  albumGain %f\n",info->haveAlbumGain, info->albumGain);
    fprintf(stderr, "haveAlbumPeak       %d  albumPeak %f\n",info->haveAlbumPeak, info->albumPeak);
    fprintf(stderr, "haveAlbumMinMaxGain %d  min %d  max %d\n",info->haveAlbumMinMaxGain, info->albumMinGain, info->albumMaxGain);
    fprintf(stderr, "haveTrackGain       %d  trackGain %f\n",info->haveTrackGain, info->trackGain);
    fprintf(stderr, "haveTrackPeak       %d  trackPeak %f\n",info->haveTrackPeak, info->trackPeak);
    fprintf(stderr, "haveMinMaxGain      %d  min %d  max %d\n",info->haveMinMaxGain, info->minGain, info->maxGain);
}

@implementation Mp3GainAdapter

- (id)init
{
    self = [super init];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

+(int)mp3gainMain:(int)argc mainArgs:(char**)argv withItem:(m3gInputItem*)m3item withProgress:(NSProgressIndicator*)progBar {
    MPSTR mp;
    unsigned long ok;
    int mode;
    int crcflag;
    unsigned char *Xingcheck;
    unsigned long frame;
    int nchan;
    int bitridx;
    int freqidx;
    long bytesinframe;
    double dBchange;
    double dblGainChange;
    int intGainChange = 0;
    int intAlbumGainChange = 0;
    int nprocsamp;
    int first = 1;
    int mainloop;
    Float_t maxsample;
    Float_t lsamples[1152];
    Float_t rsamples[1152];
    unsigned char maxgain;
    unsigned char mingain;
    int ignoreClipWarning = 0;
    int autoClip = 0;
    int applyTrack = 0;
    int applyAlbum = 0;
    int analysisTrack = 0;
    char analysisError = 0;
    int fileStart;
    int databaseFormat = 0;
    int i;
    int *fileok;
    int goAhead;
    int directGain = 0;
    int directSingleChannelGain = 0;
    int directGainVal = 0;
    int mp3GainMod = 0;
    double dBGainMod = 0;
    int mpegver;
    int sideinfo_len;
    long gFilesize = 0;
    int decodeSuccess;
    struct MP3GainTagInfo *tagInfo;
    struct MP3GainTagInfo *curTag;
    struct FileTagsStruct *fileTags;
    int albumRecalc;
    double curAlbumGain = 0;
    double curAlbumPeak = 0;
    unsigned char curAlbumMinGain = 0;
    unsigned char curAlbumMaxGain = 0;
    char chtmp;
    
#ifdef AACGAIN
    AACGainHandle *aacInfo;
#endif
    
    gSuccess = 1;
    
    if (argc < 2) {
        errUsage(argv[0]);
    }
    
    maxAmpOnly = 0;
    saveTime = 0;
    fileStart = 1;
    numFiles = 0;
    
    for (i = 1; i < argc; i++) {
        if (((argv[i][0] == '/')||(argv[i][0] == '-'))&&
            (strlen(argv[i])==2)) {
            fileStart++;
            switch(argv[i][1]) {
                case 'a':
                case 'A':
                    applyTrack = 0;
                    applyAlbum = !0;
                    break;
                    
                case 'c':
                case 'C':
                    ignoreClipWarning = !0;
                    break;
                    
                case 'd':
                case 'D':
                    if (argv[i][2] != '\0') {
                        dBGainMod = atof(argv[i]+2);
                    }
                    else {
                        if (i+1 < argc) {
                            dBGainMod = atof(argv[i+1]);
                            i++;
                            fileStart++;
                        }
                        else {
                            errUsage(argv[0]);
                        }
                    }
                    break;
                    
                case 'f':
                case 'F':
                    Reckless = 1;
                    break;
                    
                case 'g':
                case 'G':
                    directGain = !0;
                    directSingleChannelGain = 0;
                    if (argv[i][2] != '\0') {
                        directGainVal = atoi(argv[i]+2);
                    }
                    else {
                        if (i+1 < argc) {
                            directGainVal = atoi(argv[i+1]);
                            i++;
                            fileStart++;
                        }
                        else {
                            errUsage(argv[0]);
                        }
                    }
                    break;
                    
                case 'h':
                case 'H':
                case '?':
                    if ((argv[i][2] == 'w')||(argv[i][2] == 'W')) {
                        wrapExplanation();
                    }
                    else {
                        if (i+1 < argc) {
                            if ((argv[i+1][0] == 'w')||(argv[i+1][0] =='W'))
                                wrapExplanation();
                        }
                        else {
                            fullUsage(argv[0]);
                        }
                    }
                    fullUsage(argv[0]);
                    break;
                    
                case 'k':
                case 'K':
                    autoClip = !0;
                    break;
                    
                case 'l':
                case 'L':
                    directSingleChannelGain = !0;
                    directGain = 0;
                    if (argv[i][2] != '\0') {
                        whichChannel = atoi(argv[i]+2);
                        if (i+1 < argc) {
                            directGainVal = atoi(argv[i+1]);
                            i++;
                            fileStart++;
                        }			
                        else {
                            errUsage(argv[0]);
                        }
                    }
                    else {
                        if (i+2 < argc) {
                            whichChannel = atoi(argv[i+1]);
                            i++;
                            fileStart++;
                            directGainVal = atoi(argv[i+1]);
                            i++;
                            fileStart++;
                        }
                        else {
                            errUsage(argv[0]);
                        }
                    }
                    break;
                    
                case 'm':
                case 'M':
                    if (argv[i][2] != '\0') {
                        mp3GainMod = atoi(argv[i]+2);
                    }
                    else {
                        if (i+1 < argc) {
                            mp3GainMod = atoi(argv[i+1]);
                            i++;
                            fileStart++;
                        }
                        else {
                            errUsage(argv[0]);
                        }
                    }
                    break;
                    
                case 'o':
                case 'O':
                    databaseFormat = !0;
                    break;
                    
                case 'p':
                case 'P':
                    saveTime = !0;
                    break;
                    
                case 'q':
                case 'Q':
                    QuietMode = !0;
                    break;
                    
                case 'r':
                case 'R':
                    applyTrack = !0;
                    applyAlbum = 0;
                    break;
                    
                case 's':
                case 'S':
                    chtmp = 0;
                    if (argv[i][2] == '\0') {
                        if (i+1 < argc) {
                            i++;
                            fileStart++;
                            chtmp = argv[i][0];
                        } else {
                            errUsage(argv[0]);
                        }
                    } else {
                        chtmp = argv[i][2];
                    }
                    switch (chtmp) {
                        case 'c':
                        case 'C':
                            checkTagOnly = !0;
                            break;
                        case 'd':
                        case 'D':
                            deleteTag = !0;
                            break;
                        case 's':
                        case 'S':
                            skipTag = !0;
                            break;
                        case 'r':
                        case 'R':
                            forceRecalculateTag = !0;
                            break;
                        case 'i':
                        case 'I':
                            useId3 = 1;
                            break;
                        case 'a':
                        case 'A':
                            useId3 = 0;
                            break;
                        default:
                            errUsage(argv[0]);
                    }
                    
                    break;
                    
                case 't':
                case 'T':
                    UsingTemp = !0;
                    break;
                    
                case 'u':
                case 'U':
                    undoChanges = !0;
                    break;
                    
                case 'v':
                case 'V':
                    showVersion(argv[0]);
                    fclose(stdout);
                    fclose(stderr);
                    exit(0);
                    
                case 'w':
                case 'W':
                    wrapGain = !0;
                    break;
                    
                case 'x':
                case 'X':
                    maxAmpOnly = !0;
                    break;
                    
                case 'e':
                case 'E':
                    analysisTrack = !0;
                    break;
                    
                default:
                    fprintf(stderr,"I don't recognize option %s\n",argv[i]);
            }
        }
    }
    
    /* now stored in tagInfo---  maxsample = malloc(sizeof(Float_t) * argc); */
    fileok = (int *)malloc(sizeof(int) * argc);
    /* now stored in tagInfo---  maxgain = malloc(sizeof(unsigned char) * argc); */
    /* now stored in tagInfo---  mingain = malloc(sizeof(unsigned char) * argc); */
    tagInfo = (struct MP3GainTagInfo *)calloc(argc, sizeof(struct MP3GainTagInfo));
    fileTags = (struct FileTagsStruct *)malloc(sizeof(struct FileTagsStruct) * argc);
    
#ifdef AACGAIN
    aacInfo = (AACGainHandle)malloc(sizeof(AACGainHandle) * argc);
#endif
    
    if (databaseFormat) {
        if (checkTagOnly) {
            fprintf(stdout,"File\tMP3 gain\tdB gain\tMax Amplitude\tMax global_gain\tMin global_gain\tAlbum gain\tAlbum dB gain\tAlbum Max Amplitude\tAlbum Max global_gain\tAlbum Min global_gain\n");
        } else if (undoChanges) {
            fprintf(stdout,"File\tleft global_gain change\tright global_gain change\n");
        } else {
            fprintf(stdout,"File\tMP3 gain\tdB gain\tMax Amplitude\tMax global_gain\tMin global_gain\n");
        }
        fflush(stdout);
    }
    
    /* read all the tags first */
    totFiles = argc - fileStart;
    for (mainloop = fileStart; mainloop < argc; mainloop++) {
        fileok[mainloop] = 0;
        curfilename = argv[mainloop];
        fileTags[mainloop].apeTag = NULL;
        fileTags[mainloop].lyrics3tag = NULL;
        fileTags[mainloop].id31tag = NULL;
        tagInfo[mainloop].dirty = 0;
        tagInfo[mainloop].haveAlbumGain = 0;
        tagInfo[mainloop].haveAlbumPeak = 0;
        tagInfo[mainloop].haveTrackGain = 0;
        tagInfo[mainloop].haveTrackPeak = 0;
        tagInfo[mainloop].haveUndo = 0;
        tagInfo[mainloop].haveMinMaxGain = 0;
        tagInfo[mainloop].haveAlbumMinMaxGain = 0;
        tagInfo[mainloop].recalc = 0;
        
#ifdef AACGAIN
        //check for aac file; open it if found
        //note: we try to open aac even if /f (reckless)
        if (aac_open(curfilename, UsingTemp, saveTime, &aacInfo[mainloop]) != 0)
        {
            //in case of any errors, don't continue processing so there is no risk of corrupting
            //a bad file
            passError(MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                      curfilename, " is not a valid mp4/m4a file.\n");
            exit(1);
        }
#endif
        
        if ((!skipTag)&&(!deleteTag)) {
#ifdef AACGAIN
            if (aacInfo[mainloop])
            {
                if (!skipTag)
                    ReadAacTags(aacInfo[mainloop], &(tagInfo[mainloop]));
            }
            else
#endif
            {
                ReadMP3GainAPETag(curfilename,&(tagInfo[mainloop]),&(fileTags[mainloop]));
                if (useId3) {
                    if (tagInfo[mainloop].haveTrackGain || tagInfo[mainloop].haveAlbumGain ||
                        tagInfo[mainloop].haveMinMaxGain || tagInfo[mainloop].haveAlbumMinMaxGain ||
                        tagInfo[mainloop].haveUndo) {
                        /* Mark the file dirty to force upgrade to ID3v2 */
                        tagInfo[mainloop].dirty = 1;
                    }
                    ReadMP3GainID3Tag(curfilename,&(tagInfo[mainloop]));
                }
            }
            /*fprintf(stdout,"Read previous tags from %s\n",curfilename);
             dumpTaginfo(&(tagInfo[mainloop]));*/
            if (forceRecalculateTag) {
                if (tagInfo[mainloop].haveAlbumGain) {
                    tagInfo[mainloop].dirty = !0;
                    tagInfo[mainloop].haveAlbumGain = 0;
                }
                if (tagInfo[mainloop].haveAlbumPeak) {
                    tagInfo[mainloop].dirty = !0;
                    tagInfo[mainloop].haveAlbumPeak = 0;
                }
                if (tagInfo[mainloop].haveTrackGain) {
                    tagInfo[mainloop].dirty = !0;
                    tagInfo[mainloop].haveTrackGain = 0;
                }
                if (tagInfo[mainloop].haveTrackPeak) {
                    tagInfo[mainloop].dirty = !0;
                    tagInfo[mainloop].haveTrackPeak = 0;
                }
                /* NOT Undo information! 
                 if (tagInfo[mainloop].haveUndo) {
                 tagInfo[mainloop].dirty = !0;
                 tagInfo[mainloop].haveUndo = 0;
                 }
                 */
                if (tagInfo[mainloop].haveMinMaxGain) {
                    tagInfo[mainloop].dirty = !0;
                    tagInfo[mainloop].haveMinMaxGain = 0;
                }
                if (tagInfo[mainloop].haveAlbumMinMaxGain) {
                    tagInfo[mainloop].dirty = !0;
                    tagInfo[mainloop].haveAlbumMinMaxGain = 0;
                }
            }
        }
    }
    
    /* check if we need to actually process the file(s) */
    albumRecalc = forceRecalculateTag || skipTag ? FULL_RECALC : 0;
    if ((!skipTag)&&(!deleteTag)&&(!forceRecalculateTag)) {
        /* we're not automatically recalculating, so check if we already have all the information */
        if (argc - fileStart > 1) {
            curAlbumGain = tagInfo[fileStart].albumGain;
            curAlbumPeak = tagInfo[fileStart].albumPeak;
            curAlbumMinGain = tagInfo[fileStart].albumMinGain;
            curAlbumMaxGain = tagInfo[fileStart].albumMaxGain;
        }
        for (mainloop = fileStart; mainloop < argc; mainloop++) {
            if (!maxAmpOnly) { /* we don't care about these things if we're only looking for max amp */
                if (argc - fileStart > 1 && !applyTrack && !analysisTrack) { /* only check album stuff if more than one file in the list */
                    if (!tagInfo[mainloop].haveAlbumGain) {
                        albumRecalc |= FULL_RECALC;
                    } else if (tagInfo[mainloop].albumGain != curAlbumGain) {
                        albumRecalc |= FULL_RECALC;
                    }
                }
                if (!tagInfo[mainloop].haveTrackGain) {
                    tagInfo[mainloop].recalc |= FULL_RECALC;
                }
            }
            if (argc - fileStart > 1 && !applyTrack && !analysisTrack) { /* only check album stuff if more than one file in the list */
                if (!tagInfo[mainloop].haveAlbumPeak) {
                    albumRecalc |= AMP_RECALC;
                } else if (tagInfo[mainloop].albumPeak != curAlbumPeak) {
                    albumRecalc |= AMP_RECALC;
                }
                if (!tagInfo[mainloop].haveAlbumMinMaxGain) {
                    albumRecalc |= MIN_MAX_GAIN_RECALC;
                } else if (tagInfo[mainloop].albumMaxGain != curAlbumMaxGain) {
                    albumRecalc |= MIN_MAX_GAIN_RECALC;
                } else if (tagInfo[mainloop].albumMinGain != curAlbumMinGain) {
                    albumRecalc |= MIN_MAX_GAIN_RECALC;
                }
            }
            if (!tagInfo[mainloop].haveTrackPeak) {
                tagInfo[mainloop].recalc |= AMP_RECALC;
            }
            if (!tagInfo[mainloop].haveMinMaxGain) {
                tagInfo[mainloop].recalc |= MIN_MAX_GAIN_RECALC;
            }
        }
    }
    
    for (mainloop = fileStart; mainloop < argc; mainloop++) {
#ifdef AACGAIN
        AACGainHandle aacH = aacInfo[mainloop];
#endif
        memset(&mp, 0, sizeof(mp));
        
        // if the entire Album requires some kind of recalculation, then each track needs it
        tagInfo[mainloop].recalc |= albumRecalc; 
        
        curfilename = argv[mainloop];
        if (checkTagOnly) {
            curTag = tagInfo + mainloop;
            if (curTag->haveTrackGain) {
                dblGainChange = curTag->trackGain / (5.0 * log10(2.0));
                
                if (fabs(dblGainChange) - (double)((int)(fabs(dblGainChange))) < 0.5)
                    intGainChange = (int)(dblGainChange);
                else
                    intGainChange = (int)(dblGainChange) + (dblGainChange < 0 ? -1 : 1);
            }
            if (curTag->haveAlbumGain) {
                dblGainChange = curTag->albumGain / (5.0 * log10(2.0));
                
                if (fabs(dblGainChange) - (double)((int)(fabs(dblGainChange))) < 0.5)
                    intAlbumGainChange = (int)(dblGainChange);
                else
                    intAlbumGainChange = (int)(dblGainChange) + (dblGainChange < 0 ? -1 : 1);
            }
            if (!databaseFormat) {
                fprintf(stdout,"%s\n",argv[mainloop]);
                if (curTag->haveTrackGain) {
                    fprintf(stdout,"Recommended \"Track\" dB change: %f\n",curTag->trackGain);
                    fprintf(stdout,"Recommended \"Track\" mp3 gain change: %d\n",intGainChange);
                    if (curTag->haveTrackPeak) {
                        if (curTag->trackPeak * (Float_t)(pow(2.0,(double)(intGainChange)/4.0)) > 1.0) {
                            fprintf(stdout,"WARNING: some clipping may occur with this gain change!\n");
                        }
                    }
                }
                if (curTag->haveTrackPeak)
                    fprintf(stdout,"Max PCM sample at current gain: %f\n",curTag->trackPeak * 32768.0);
                if (curTag->haveMinMaxGain) {
                    fprintf(stdout,"Max mp3 global gain field: %d\n",curTag->maxGain);
                    fprintf(stdout,"Min mp3 global gain field: %d\n",curTag->minGain);
                }
                if (curTag->haveAlbumGain) {
                    fprintf(stdout,"Recommended \"Album\" dB change: %f\n",curTag->albumGain);
                    fprintf(stdout,"Recommended \"Album\" mp3 gain change: %d\n",intAlbumGainChange);
                    if (curTag->haveTrackPeak) {
                        if (curTag->trackPeak * (Float_t)(pow(2.0,(double)(intAlbumGainChange)/4.0)) > 1.0) {
                            fprintf(stdout,"WARNING: some clipping may occur with this gain change!\n");
                        }
                    }
                }
                if (curTag->haveAlbumPeak) {
                    fprintf(stdout,"Max Album PCM sample at current gain: %f\n",curTag->albumPeak * 32768.0);
                }
                if (curTag->haveAlbumMinMaxGain) {
                    fprintf(stdout,"Max Album mp3 global gain field: %d\n",curTag->albumMaxGain);
                    fprintf(stdout,"Min Album mp3 global gain field: %d\n",curTag->albumMinGain);
                }
                fprintf(stdout,"\n");
            } else {
                fprintf(stdout,"%s\t",argv[mainloop]);
                if (curTag->haveTrackGain) {
                    fprintf(stdout,"%d\t",intGainChange);
                    fprintf(stdout,"%f\t",curTag->trackGain);
                } else {
                    fprintf(stdout,"NA\tNA\t");
                }
                if (curTag->haveTrackPeak) {
                    fprintf(stdout,"%f\t",curTag->trackPeak * 32768.0);
                } else {
                    fprintf(stdout,"NA\t");
                }
                if (curTag->haveMinMaxGain) {
                    fprintf(stdout,"%d\t",curTag->maxGain);
                    fprintf(stdout,"%d\t",curTag->minGain);
                } else {
                    fprintf(stdout,"NA\tNA\t");
                }
                if (curTag->haveAlbumGain) {
                    fprintf(stdout,"%d\t",intAlbumGainChange);
                    fprintf(stdout,"%f\t",curTag->albumGain);
                } else {
                    fprintf(stdout,"NA\tNA\t");
                }
                if (curTag->haveAlbumPeak) {
                    fprintf(stdout,"%f\t",curTag->albumPeak * 32768.0);
                } else {
                    fprintf(stdout,"NA\t");
                }
                if (curTag->haveAlbumMinMaxGain) {
                    fprintf(stdout,"%d\t",curTag->albumMaxGain);
                    fprintf(stdout,"%d\n",curTag->albumMinGain);
                } else {
                    fprintf(stdout,"NA\tNA\n");
                }
                fflush(stdout);
            }
        }
        else if (undoChanges) {
            directGain = !0; /* so we don't write the tag a second time */
            if ((tagInfo[mainloop].haveUndo)&&(tagInfo[mainloop].undoLeft || tagInfo[mainloop].undoRight)) {
                if ((!QuietMode)&&(!databaseFormat))
                    fprintf(stderr,"Undoing mp3gain changes (%d,%d) to %s...\n", tagInfo[mainloop].undoLeft, tagInfo[mainloop].undoRight, argv[mainloop]);
                
                if (databaseFormat)
                    fprintf(stdout,"%s\t%d\t%d\n", argv[mainloop], tagInfo[mainloop].undoLeft, tagInfo[mainloop].undoRight);
                
                changeGainAndTag(argv[mainloop] AACGAIN_ARG(aacH),
                                 tagInfo[mainloop].undoLeft, tagInfo[mainloop].undoRight,
                                 tagInfo + mainloop, fileTags + mainloop);
                
            } else {
                if (databaseFormat) {
                    fprintf(stdout,"%s\t0\t0\n",argv[mainloop]);
                } else if (!QuietMode) {
                    if (tagInfo[mainloop].haveUndo) {
                        fprintf(stderr,"No changes to undo in %s\n",argv[mainloop]);
                    } else {
                        fprintf(stderr,"No undo information in %s\n",argv[mainloop]);
                    }
                }
            }
        }
        else if (directSingleChannelGain) {
            if (!QuietMode)
                fprintf(stderr,"Applying gain change of %d to CHANNEL %d of %s...\n",directGainVal,whichChannel,argv[mainloop]);
            if (whichChannel) { /* do right channel */
                if (skipTag) {
                    changeGain(argv[mainloop] AACGAIN_ARG(aacH), 0, directGainVal);
                } else {
                    changeGainAndTag(argv[mainloop] AACGAIN_ARG(aacH), 0, directGainVal, tagInfo + mainloop, fileTags + mainloop);
                }
            }
            else { /* do left channel */
                if (skipTag) {
                    changeGain(argv[mainloop] AACGAIN_ARG(aacH), directGainVal, 0);
                } else {
                    changeGainAndTag(argv[mainloop] AACGAIN_ARG(aacH), directGainVal, 0, tagInfo + mainloop, fileTags + mainloop);
                }
            }
            if ((!QuietMode) && (gSuccess == 1))
                fprintf(stderr,"\ndone\n");
        }
        else if (directGain) {
            if (!QuietMode)
                fprintf(stderr,"Applying gain change of %d to %s...\n",directGainVal,argv[mainloop]);
            if (skipTag) {
                changeGain(argv[mainloop] AACGAIN_ARG(aacH), directGainVal, directGainVal);
            } else {
                changeGainAndTag(argv[mainloop] AACGAIN_ARG(aacH),
                                 directGainVal,directGainVal, tagInfo + mainloop, fileTags + mainloop);
            }
            if ((!QuietMode) && (gSuccess == 1))
                fprintf(stderr,"\ndone\n");
        }
        else if (deleteTag) {
#ifdef AACGAIN
            if (aacH)
                aac_clear_rg_tags(aacH);
            else
#endif
            {
                RemoveMP3GainAPETag(argv[mainloop], saveTime);
                if (useId3) {
                    RemoveMP3GainID3Tag(argv[mainloop], saveTime);
                }
            }
            if ((!QuietMode)&&(!databaseFormat))
                fprintf(stderr,"Deleting tag info of %s...\n", argv[mainloop]);
            if (databaseFormat)
                fprintf(stdout,"%s\tNA\tNA\tNA\tNA\tNA\n", argv[mainloop]);
        }
        else {
            if (!databaseFormat)
                fprintf(stdout,"%s\n",argv[mainloop]);
            
            if (tagInfo[mainloop].recalc > 0) {
                gFilesize = getSizeOfFile(argv[mainloop]);
                
#ifdef AACGAIN
                if (!aacH)
#endif
                    inf = fopen(argv[mainloop],"rb");
            }
            
#ifdef AACGAIN
            if (!aacH&&(inf == NULL)&&(tagInfo[mainloop].recalc > 0))
#else
                if ((inf == NULL)&&(tagInfo[mainloop].recalc > 0))
#endif
                {
                    fprintf(stdout, "Can't open %s for reading\n",argv[mainloop]);
                    fflush(stdout);
                }
                else {
#ifdef AACGAIN
                    if (!aacH)
#endif
                        InitMP3(&mp);
                    if (tagInfo[mainloop].recalc == 0) {
                        maxsample = tagInfo[mainloop].trackPeak * 32768.0;
                        maxgain = tagInfo[mainloop].maxGain;
                        mingain = tagInfo[mainloop].minGain;
                        ok = !0;
                    } else {
                        if (!((tagInfo[mainloop].recalc & FULL_RECALC)||(tagInfo[mainloop].recalc & AMP_RECALC))) { /* only min/max rescan */
                            maxsample = tagInfo[mainloop].trackPeak * 32768.0;
                        }
                        else {
                            maxsample = 0;
                        }
#ifdef AACGAIN
                        if (aacH)
                        {
                            int rc;
                            
                            if (first) {
                                lastfreq = aac_get_sample_rate(aacH);
                                InitGainAnalysis((long)lastfreq);
                                analysisError = 0;
                                first = 0;
                            }
                            else {
                                if (aac_get_sample_rate(aacH) != lastfreq) {
                                    lastfreq = aac_get_sample_rate(aacH);
                                    ResetSampleFrequency ((long)lastfreq);
                                }
                            }
                            
                            numFiles++;
                            
                            if (maxAmpOnly)
                                rc = aac_compute_peak(aacH, &maxsample, &mingain, &maxgain, 
                                                      QuietMode ? NULL : reportPercentAnalyzed);
                            else
                                rc = aac_compute_gain(aacH, &maxsample, &mingain, &maxgain, 
                                                      QuietMode ? NULL : reportPercentAnalyzed);
                            //in case of any error, bail to avoid corrupting file
                            if (rc != 0)
                            {
                                passError(MP3GAIN_FILEFORMAT_NOTSUPPORTED, 2,
                                          curfilename, " is not a valid mp4/m4a file.\n");
                                exit(1);
                            }
                            ok = !0;
                        } else 
#endif
                        {
                            BadLayer = 0;
                            LayerSet = Reckless;
                            maxgain = 0;
                            mingain = 255;
                            inbuffer = 0;
                            filepos = 0;
                            bitidx = 0;
                            ok = fillBuffer(0);
                        }
                    }
                    if (ok) {
#ifdef AACGAIN
                        if (!aacH && (tagInfo[mainloop].recalc > 0)) 
#else
                            if (tagInfo[mainloop].recalc > 0) 
#endif
                            {
                                wrdpntr = buffer;
                                
                                ok = skipID3v2();
                                
                                ok = frameSearch(!0);
                            }
                        
#ifdef AACGAIN
                        if (!ok && !aacH) 
#else
                            if (!ok) 
#endif
                            {
                                if (!BadLayer) {
                                    NSAlert* nsa = [NSAlert alertWithMessageText:NSLocalizedStringFromTable(@"Not_MP3_file", @"ui_text", @"Not MP3") defaultButton:NSLocalizedStringFromTable(@"OK", @"ui_text", @"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:NSLocalizedStringFromTable(@"No_MP3_Frames", @"ui_text", @"No valid mp3 frames in file")];
                                    [nsa performSelectorOnMainThread:@selector(runModal) withObject:nil waitUntilDone:TRUE];
                                    fprintf(stdout,"Can't find any valid MP3 frames in file %s\n",argv[mainloop]);
                                    fflush(stdout);
                                }
                            }
                            else {
                                LayerSet = 1; /* We've found at least one valid layer 3 frame.
                                               * Assume any later layer 1 or 2 frames are just
                                               * bitstream corruption
                                               */
                                fileok[mainloop] = !0;
#ifdef AACGAIN
                                if (!aacH || (tagInfo[mainloop].recalc == 0))
#endif
                                    numFiles++;
                                
#ifdef AACGAIN
                                if (!aacH && (tagInfo[mainloop].recalc > 0)) 
#else
                                    if (tagInfo[mainloop].recalc > 0) 
#endif
                                    {
                                        mode = (curframe[3] >> 6) & 3;
                                        
                                        if ((curframe[1] & 0x08) == 0x08) /* MPEG 1 */
                                            sideinfo_len = ((curframe[3] & 0xC0) == 0xC0) ? 4 + 17 : 4 + 32;
                                        else                /* MPEG 2 */
                                            sideinfo_len = ((curframe[3] & 0xC0) == 0xC0) ? 4 + 9 : 4 + 17;
                                        
                                        if (!(curframe[1] & 0x01))
                                            sideinfo_len += 2;
                                        
                                        Xingcheck = curframe + sideinfo_len;
                                        //LAME CBR files have "Info" tags, not "Xing" tags
                                        if ((Xingcheck[0] == 'X' && Xingcheck[1] == 'i' && Xingcheck[2] == 'n' && Xingcheck[3] == 'g') ||
                                            (Xingcheck[0] == 'I' && Xingcheck[1] == 'n' && Xingcheck[2] == 'f' && Xingcheck[3] == 'o')) {
                                            bitridx = (curframe[2] >> 4) & 0x0F;
                                            if (bitridx == 0) {
                                                fprintf(stdout, "%s is free format (not currently supported)\n",curfilename);
                                                fflush(stdout);
                                                ok = 0;
                                            }
                                            else {
                                                mpegver = (curframe[1] >> 3) & 0x03;
                                                freqidx = (curframe[2] >> 2) & 0x03;
                                                
                                                bytesinframe = arrbytesinframe[bitridx] + ((curframe[2] >> 1) & 0x01);
                                                
                                                wrdpntr = curframe + bytesinframe;
                                                
                                                ok = frameSearch(0);
                                            }
                                        }
                                        
                                        frame = 1;
                                        
                                        if (!maxAmpOnly) {
                                            if (ok) {
                                                mpegver = (curframe[1] >> 3) & 0x03;
                                                freqidx = (curframe[2] >> 2) & 0x03;
                                                
                                                if (first) {
                                                    lastfreq = frequency[mpegver][freqidx];
                                                    InitGainAnalysis((long)(lastfreq * 1000.0));
                                                    analysisError = 0;
                                                    first = 0;
                                                }
                                                else {
                                                    if (frequency[mpegver][freqidx] != lastfreq) {
                                                        lastfreq = frequency[mpegver][freqidx];
                                                        ResetSampleFrequency ((long)(lastfreq * 1000.0));
                                                    }
                                                }
                                            }
                                        }
                                        else {
                                            analysisError = 0;
                                        }
                                        
                                        while (ok) {
                                            bitridx = (curframe[2] >> 4) & 0x0F;
                                            if (bitridx == 0) {
                                                fprintf(stdout,"%s is free format (not currently supported)\n",curfilename);
                                                fflush(stdout);
                                                ok = 0;
                                            }
                                            else {
                                                mpegver = (curframe[1] >> 3) & 0x03;
                                                crcflag = curframe[1] & 0x01;
                                                freqidx = (curframe[2] >> 2) & 0x03;
                                                
                                                bytesinframe = arrbytesinframe[bitridx] + ((curframe[2] >> 1) & 0x01);
                                                mode = (curframe[3] >> 6) & 0x03;
                                                nchan = (mode == 3) ? 1 : 2;
                                                
                                                if (inbuffer >= bytesinframe) {
                                                    lSamp = lsamples;
                                                    rSamp = rsamples;
                                                    maxSamp = &maxsample;
                                                    maxGain = &maxgain;
                                                    minGain = &mingain;
                                                    procSamp = 0;
                                                    if ((tagInfo[mainloop].recalc & AMP_RECALC) || (tagInfo[mainloop].recalc & FULL_RECALC)) {
#ifdef WIN32
#ifndef __GNUC__
                                                        __try { /* this is the Windows try/catch equivalent for C.
                                                                 If you want this in some other system, you should be
                                                                 able to use the C++ try/catch mechanism. I've tried to keep
                                                                 all of the code plain C, though. This error only
                                                                 occurs with _very_ corrupt mp3s, so I don't know if you'll
                                                                 think it's worth the trouble */
#endif
#endif
                                                            decodeSuccess = decodeMP3(&mp,curframe,bytesinframe,&nprocsamp);
#ifdef WIN32
#ifndef __GNUC__
                                                        }
                                                        __except(1) {
                                                            fprintf(stderr,"Error analyzing %s. This mp3 has some very corrupt data.\n",curfilename);
                                                            fclose(stdout);
                                                            fclose(stderr);
                                                            exit(1);
                                                        }
#endif
#endif
                                                    } else { /* don't need to actually decode frame, 
                                                              just scan for min/max gain values */
                                                        decodeSuccess = !MP3_OK;
                                                        scanFrameGain();//curframe);
                                                    }
                                                    if (decodeSuccess == MP3_OK) {
                                                        if ((!maxAmpOnly)&&(tagInfo[mainloop].recalc & FULL_RECALC)) {
                                                            if (AnalyzeSamples(lsamples,rsamples,procSamp/nchan,nchan) == GAIN_ANALYSIS_ERROR) {
                                                                fprintf(stderr,"Error analyzing further samples (max time reached)          \n");
                                                                analysisError = !0;
                                                                ok = 0;
                                                            }
                                                        }
                                                    }
                                                }
                                                
                                                
                                                if (!analysisError) {
                                                    wrdpntr = curframe+bytesinframe;
                                                    ok = frameSearch(0);
                                                }
                                                
                                                if (!QuietMode) {
                                                    if ( !(++frame % 200)) {
                                                        reportPercentAnalyzed((int)(((double)(filepos-(inbuffer-(curframe+bytesinframe-buffer))) * 100.0) / gFilesize),gFilesize);
                                                        [progBar setDoubleValue:(((double)(filepos-(inbuffer-(curframe+bytesinframe-buffer))) * 100.0) / gFilesize)];
                                                    }
                                                }
                                            }
                                        }
                                    }
                                
                                if (!QuietMode)
                                    fprintf(stderr,"                                                 \r");
                                
                                if (tagInfo[mainloop].recalc & FULL_RECALC) {
                                    if (maxAmpOnly)
                                        dBchange = 0;
                                    else
                                        dBchange = GetTitleGain();
                                } else {
                                    dBchange = tagInfo[mainloop].trackGain;
                                }
                                
                                if (dBchange == GAIN_NOT_ENOUGH_SAMPLES) {
                                    fprintf(stdout,"Not enough samples in %s to do analysis\n",argv[mainloop]);
                                    fflush(stdout);
                                    numFiles--;
                                }
                                else {
                                    /* even if skipTag is on, we'll leave this part running just to store the minpeak and maxpeak */
                                    curTag = tagInfo + mainloop;
                                    if (!maxAmpOnly) {
                                        if ( /* if we don't already have a tagged track gain OR we have it, but it doesn't match */
                                            !curTag->haveTrackGain || 
                                            (curTag->haveTrackGain && 
                                             (fabs(dBchange - curTag->trackGain) >= 0.01))
                                            ) {
                                            curTag->dirty = !0;
                                            curTag->haveTrackGain = 1;
                                            curTag->trackGain = dBchange;
                                        }
                                    }						
                                    if (!curTag->haveMinMaxGain || /* if minGain or maxGain doesn't match tag */
                                        (curTag->haveMinMaxGain && 
                                         (curTag->minGain != mingain || curTag->maxGain != maxgain))) {
                                            curTag->dirty = !0;
                                            curTag->haveMinMaxGain = !0;
                                            curTag->minGain = mingain;
                                            curTag->maxGain = maxgain;
                                        }
                                    
                                    if (!curTag->haveTrackPeak ||
                                        (curTag->haveTrackPeak &&
                                         (fabs(maxsample - (curTag->trackPeak) * 32768.0) >= 3.3))) {
                                            curTag->dirty = !0;
                                            curTag->haveTrackPeak = !0;
                                            curTag->trackPeak = maxsample / 32768.0;
                                        }
                                    /* the TAG version of the suggested Track Gain should ALWAYS be based on the 89dB standard.
                                     So we don't modify the suggested gain change until this point */
                                    
                                    m3item.volume = 89.0f - dBchange;
                                    
                                    dBchange += dBGainMod;
                                    
                                    dblGainChange = dBchange / (5.0 * log10(2.0));
                                    
                                    if (fabs(dblGainChange) - (double)((int)(fabs(dblGainChange))) < 0.5)
                                        intGainChange = (int)(dblGainChange);
                                    else
                                        intGainChange = (int)(dblGainChange) + (dblGainChange < 0 ? -1 : 1);
                                    intGainChange += mp3GainMod;
                                    
                                    if (databaseFormat) {
                                        fprintf(stdout,"%s\t%d\t%f\t%f\t%d\t%d\n",argv[mainloop],intGainChange,dBchange,maxsample,maxgain,mingain);
                                        fflush(stdout);
                                    }
                                    m3item.track_gain = dBchange;
                                    m3item.clipping = NO;
                                    if ((!applyTrack)&&(!applyAlbum)) {
                                        if (!databaseFormat) {
                                            fprintf(stdout,"Recommended \"Track\" dB change: %f\n",dBchange);
                                            fprintf(stdout,"Recommended \"Track\" mp3 gain change: %d\n",intGainChange);
                                            if (maxsample * (Float_t)(pow(2.0,(double)(intGainChange)/4.0)) > 32767.0) {
                                                fprintf(stdout,"WARNING: some clipping may occur with this gain change!\n");
                                                m3item.clipping = YES;
                                            }
                                            fprintf(stdout,"Max PCM sample at current gain: %f\n",maxsample);
                                            fprintf(stdout,"Max mp3 global gain field: %d\n",maxgain);
                                            fprintf(stdout,"Min mp3 global gain field: %d\n",mingain);
                                            fprintf(stdout,"\n");
                                        }
                                    }
                                    else if (applyTrack) {
                                        first = !0; /* don't keep track of Album gain */
                                        if (inf)
                                            fclose(inf);
                                        inf = NULL;
                                        goAhead = !0;
                                        
                                        if (intGainChange == 0) {
                                            fprintf(stdout,"No changes to %s are necessary\n",argv[mainloop]);
                                            if (!skipTag && tagInfo[mainloop].dirty) {
                                                fprintf(stdout,"...but tag needs update: Writing tag information for %s\n",argv[mainloop]);
                                                WriteMP3GainTag(argv[mainloop] AACGAIN_ARG(aacInfo[mainloop]), tagInfo + mainloop, fileTags + mainloop, saveTime);
                                            }
                                        }
                                        else {
                                            if (autoClip) {
                                                int intMaxNoClipGain = (int)(floor(4.0 * log10(32767.0 / maxsample) / log10(2.0)));
                                                if (intGainChange > intMaxNoClipGain) {
                                                    fprintf(stdout,"Applying auto-clipped mp3 gain change of %d to %s\n(Original suggested gain was %d)\n",intMaxNoClipGain,argv[mainloop],intGainChange);
                                                    intGainChange = intMaxNoClipGain;
                                                }
                                            } else if (!ignoreClipWarning) {
                                                if (maxsample * (Float_t)(pow(2.0,(double)(intGainChange)/4.0)) > 32767.0) {
                                                    if (queryUserForClipping(argv[mainloop],intGainChange)) {
                                                        m3item.clipping = YES;
                                                        fprintf(stdout,"Applying mp3 gain change of %d to %s...\n",intGainChange,argv[mainloop]);
                                                    } else {
                                                        goAhead = 0;
                                                    }
                                                }
                                            }
                                            if (goAhead) {
                                                fprintf(stdout,"Applying mp3 gain change of %d to %s...\n",intGainChange,argv[mainloop]);
                                                if (skipTag) {
                                                    changeGain(argv[mainloop] AACGAIN_ARG(aacH), intGainChange, intGainChange);
                                                } else {
                                                    changeGainAndTag(argv[mainloop] AACGAIN_ARG(aacH),
                                                                     intGainChange,intGainChange, tagInfo + mainloop, fileTags + mainloop);
                                                }
                                            } else if (!skipTag && tagInfo[mainloop].dirty) {
                                                fprintf(stdout,"Writing tag information for %s\n",argv[mainloop]);
                                                WriteMP3GainTag(argv[mainloop] AACGAIN_ARG(aacH), tagInfo + mainloop, fileTags + mainloop, saveTime);
                                            }
                                        }
                                    }
                                }
                            }
                    }
                    
#ifdef AACGAIN
                    if (!aacH)
#endif
                        ExitMP3(&mp);
                    fflush(stderr);
                    fflush(stdout);
                    if (inf)
                        fclose(inf);
                    inf = NULL;			
                } 
        }
    }
    
    if ((numFiles > 0)&&(!applyTrack)&&(!analysisTrack)) {
        if (albumRecalc & FULL_RECALC) {
            if (maxAmpOnly)
                dBchange = 0;
            else
                dBchange = GetAlbumGain();
        } else {
            /* the following if-else is for the weird case where someone applies "Album" gain to
             a single file, but the file doesn't actually have an Album field */
            if (tagInfo[fileStart].haveAlbumGain)
                dBchange = tagInfo[fileStart].albumGain;
            else
                dBchange = tagInfo[fileStart].trackGain;
        }
        
        if (dBchange == GAIN_NOT_ENOUGH_SAMPLES) {
            fprintf(stdout,"Not enough samples in mp3 files to do analysis\n");
            fflush(stdout);
        }
        else {
            Float_t maxmaxsample;
            unsigned char maxmaxgain;
            unsigned char minmingain;
            maxmaxsample = 0;
            maxmaxgain = 0;
            minmingain = 255;
            for (mainloop = fileStart; mainloop < argc; mainloop++) {
                if (fileok[mainloop]) {
                    if (tagInfo[mainloop].trackPeak > maxmaxsample)
                        maxmaxsample = tagInfo[mainloop].trackPeak;
                    if (tagInfo[mainloop].maxGain > maxmaxgain)
                        maxmaxgain = tagInfo[mainloop].maxGain;
                    if (tagInfo[mainloop].minGain < minmingain)
                        minmingain = tagInfo[mainloop].minGain;
                }
            }
            
            if ((!skipTag)&&(numFiles > 1 || applyAlbum)) {
                for (mainloop = fileStart; mainloop < argc; mainloop++) {
                    curTag = tagInfo + mainloop;
                    if (!maxAmpOnly) {
                        if ( /* if we don't already have a tagged track gain OR we have it, but it doesn't match */
                            !curTag->haveAlbumGain || 
                            (curTag->haveAlbumGain && 
                             (fabs(dBchange - curTag->albumGain) >= 0.01))
                            ){
                            curTag->dirty = !0;
                            curTag->haveAlbumGain = 1;
                            curTag->albumGain = dBchange;
                        }
                    }
                    
                    if (!curTag->haveAlbumMinMaxGain || /* if albumMinGain or albumMaxGain doesn't match tag */
                        (curTag->haveAlbumMinMaxGain && 
                         (curTag->albumMinGain != minmingain || curTag->albumMaxGain != maxmaxgain))) {
                            curTag->dirty = !0;
                            curTag->haveAlbumMinMaxGain = !0;
                            curTag->albumMinGain = minmingain;
                            curTag->albumMaxGain = maxmaxgain;
                        }
                    
                    if (!curTag->haveAlbumPeak ||
                        (curTag->haveAlbumPeak &&
                         (fabs(maxmaxsample - curTag->albumPeak) >= 0.0001))) {
                            curTag->dirty = !0;
                            curTag->haveAlbumPeak = !0;
                            curTag->albumPeak = maxmaxsample;
                        }
                }
            }
            
            /* the TAG version of the suggested Album Gain should ALWAYS be based on the 89dB standard.
             So we don't modify the suggested gain change until this point */
            
            dBchange += dBGainMod;
            
            dblGainChange = dBchange / (5.0 * log10(2.0));
            if (fabs(dblGainChange) - (double)((int)(fabs(dblGainChange))) < 0.5)
                intGainChange = (int)(dblGainChange);
            else
                intGainChange = (int)(dblGainChange) + (dblGainChange < 0 ? -1 : 1);
            intGainChange += mp3GainMod;
            
            
            if (databaseFormat) {
                fprintf(stdout,"\"Album\"\t%d\t%f\t%f\t%d\t%d\n",intGainChange,dBchange,maxmaxsample * 32768.0 ,maxmaxgain,minmingain);
                fflush(stdout);
            }
            
            if (!applyAlbum) {
                if (!databaseFormat) {
                    fprintf(stdout,"\nRecommended \"Album\" dB change for all files: %f\n",dBchange);
                    fprintf(stdout,"Recommended \"Album\" mp3 gain change for all files: %d\n",intGainChange);
                    for (mainloop = fileStart; mainloop < argc; mainloop++) {
                        if (fileok[mainloop])
                            if (tagInfo[mainloop].trackPeak * (Float_t)(pow(2.0,(double)(intGainChange)/4.0)) > 1.0) {
                                fprintf(stdout,"WARNING: with this global gain change, some clipping may occur in file %s\n",argv[mainloop]);
                            }
                    }
                }
            }
            else {
                /*MAA*/			if (autoClip) {
                    /*MAA*/				int intMaxNoClipGain = (int)(floor(-4.0 * log10(maxmaxsample) / log10(2.0)));
                    /*MAA*/				if (intGainChange > intMaxNoClipGain) {
                        /*MAA*/					fprintf(stdout,"Applying auto-clipped mp3 gain change of %d to album\n(Original suggested gain was %d)\n",intMaxNoClipGain,intGainChange);
                        /*MAA*/					intGainChange = intMaxNoClipGain;
                        /*MAA*/				}
                    /*MAA*/			}
                for (mainloop = fileStart; mainloop < argc; mainloop++) {
                    if (fileok[mainloop]) {
                        goAhead = !0;
                        if (intGainChange == 0) {
                            fprintf(stdout,"\nNo changes to %s are necessary\n",argv[mainloop]);
                            if (!skipTag && tagInfo[mainloop].dirty) {
                                fprintf(stdout,"...but tag needs update: Writing tag information for %s\n",argv[mainloop]);
                                WriteMP3GainTag(argv[mainloop] AACGAIN_ARG(aacInfo[mainloop]), tagInfo + mainloop, fileTags + mainloop, saveTime);
                            }
                        }
                        else {
                            if (!ignoreClipWarning) {
                                if (tagInfo[mainloop].trackPeak * (Float_t)(pow(2.0,(double)(intGainChange)/4.0)) > 1.0){
                                    goAhead = queryUserForClipping(argv[mainloop],intGainChange);
                                    m3item.clipping = TRUE;
                                }
                            }
                            if (goAhead) {
                                fprintf(stdout,"Applying mp3 gain change of %d to %s...\n",intGainChange,argv[mainloop]);
                                if (skipTag) {
                                    changeGain(argv[mainloop] AACGAIN_ARG(aacInfo[mainloop]), intGainChange, intGainChange);
                                } else {
                                    changeGainAndTag(argv[mainloop] AACGAIN_ARG(aacInfo[mainloop]), intGainChange, intGainChange, tagInfo + mainloop, fileTags + mainloop);
                                }
                            } else if (!skipTag && tagInfo[mainloop].dirty) {
                                fprintf(stdout,"Writing tag information for %s\n",argv[mainloop]);
                                WriteMP3GainTag(argv[mainloop] AACGAIN_ARG(aacInfo[mainloop]), tagInfo + mainloop, fileTags + mainloop, saveTime);
                            }
                        }
                    }
                }
            }
        }
    }
    
    /* update file tags */
    if ((!applyTrack)&&
        (!applyAlbum)&&
        (!directGain)&&
        (!directSingleChannelGain)&&
        (!deleteTag)&&
        (!skipTag)&&
        (!checkTagOnly)) { 
        /* if we made changes, we already updated the tags */
        for (mainloop = fileStart; mainloop < argc; mainloop++) {
            if (fileok[mainloop]) {
                if (tagInfo[mainloop].dirty) {
                    WriteMP3GainTag(argv[mainloop] AACGAIN_ARG(aacInfo[mainloop]), tagInfo + mainloop, fileTags + mainloop, saveTime);
                }
            }
        }
    }
    
    free(tagInfo);
    /* now stored in tagInfo--- free(maxsample); */
    free(fileok);
    /* now stored in tagInfo--- free(maxgain); */
    /* now stored in tagInfo--- free(mingain); */
    for (mainloop = fileStart; mainloop < argc; mainloop++) {
        if (fileTags[mainloop].apeTag) {
            if (fileTags[mainloop].apeTag->otherFields) {
                free(fileTags[mainloop].apeTag->otherFields);
            }
            free(fileTags[mainloop].apeTag);
        }
        if (fileTags[mainloop].lyrics3tag) {
            free(fileTags[mainloop].lyrics3tag);
        }
        if (fileTags[mainloop].id31tag) {
            free(fileTags[mainloop].id31tag);
        }
#ifdef AACGAIN
        //close any open aac files
        if (aacInfo[mainloop])
            aac_close(aacInfo[mainloop]);
#endif
    }
    free(fileTags);
    
#ifdef AACGAIN
    free(aacInfo);
#endif
    fclose(stdout);
    fclose(stderr);
    if (gSuccess)
        return 0;
    else
        return 1;
}

#endif /* asWIN32DLL */


+(void)AnalyzeFile:(m3gInputItem*)item withVol:(double)desiredDb withProgress:(NSProgressIndicator*)progBar{
    const char* cFile = [item.filePath fileSystemRepresentation];
    const char* argList[4];
    argList[0] = "mp3gain";
    argList[1] = "-d";
    argList[2] = [[NSString stringWithFormat:@"%f",(desiredDb-89.0)] cStringUsingEncoding:[NSString defaultCStringEncoding]];
    argList[3] = cFile;
    
    [self mp3gainMain:4 mainArgs:(char**)argList withItem:item withProgress:progBar];
}

+(void)ModifyFile:(m3gInputItem*)item withVol:(double)desiredDb withProgress:(NSProgressIndicator*)progBar{
    const char* cFile = [item.filePath fileSystemRepresentation];
    const char* argList[5];
    argList[0] = "mp3gain";
    argList[1] = "-r";
    argList[2] = "-d";
    argList[3] = [[NSString stringWithFormat:@"%f",(desiredDb-89.0)] cStringUsingEncoding:[NSString defaultCStringEncoding]];
    argList[4] = cFile;
    
    [self mp3gainMain:5 mainArgs:(char**)argList withItem:item withProgress:progBar];
}
@end
