#include "apetag.h"
#include "mp3gain.h"
#include "rg_error.h"
#include <stdlib.h>
#include <stdio.h>
#include <memory.h>
#include <string.h>
#include <fcntl.h>
#ifdef WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

#ifndef WIN32
#define _stricmp strcasecmp
#endif /* WIN32 */

int ReadMP3ID3v1Tag(FILE *fi, unsigned char **tagbuff, long *tag_offset) {
    char tmp[128];

	if ( *tag_offset < 128 ) return 0;
	if ( fseek(fi, *tag_offset - 128,SEEK_SET) ) return 0;
	if ( fread(tmp, 1, 128, fi) != 128 ) return 0;
    if ( memcmp (tmp, "TAG", 3) ) return 0;

    //we have tag, so store it in buffer
	if (*tagbuff)
		free(*tagbuff);
	*tagbuff = (unsigned char *)malloc(128);
    memcpy(*tagbuff,tmp,128);
    *tag_offset -= 128;

    return 1;
}


/*
static int Lyrics3GetNumber5 ( const unsigned char* string )
{
	return ( string[0] - '0') * 10000 +
		   ( string[1] - '0') * 1000 +
		   ( string[2] - '0') * 100 +
		   ( string[3] - '0') * 10 +
		   ( string[4] - '0') * 1;
}
*/


static int Lyrics3GetNumber6 ( const unsigned char* string )
{
	return ( string[0] - '0') * 100000 +
		   ( string[1] - '0') * 10000 +
		   ( string[2] - '0') * 1000 +
		   ( string[3] - '0') * 100 +
		   ( string[4] - '0') * 10 +
		   ( string[5] - '0') * 1;
}

struct Lyrics3TagFooterStruct {
    unsigned char   Length  [6];
    unsigned char   ID      [9];
};

struct Lyrics3TagField {
	unsigned char   ID      [3];
	unsigned char   Length  [5];
};

// Reads Lyrics3 v2.0 tag
static int ReadMP3Lyrics3v2Tag ( FILE *fp, unsigned char **tagbuff, unsigned long *tagSize, unsigned char **id3tagbuff, long *tag_offset )
{
	int                                 len;
	struct Lyrics3TagFooterStruct       T;
    char                                tmpid3[128];
    char                                tmp[11];
    long                                taglen;

	if ( *tag_offset < 128 ) return 0;
    if ( fseek (fp, *tag_offset - 128, SEEK_SET) ) return 0;
    if ( fread (tmpid3, 1, 128, fp) != 128 ) return 0;
    // check for id3-tag
    if ( memcmp (tmpid3, "TAG", 3) ) return 0;
    //if we have id3-tag, put it in the id3tagbuff
	if (*id3tagbuff)
		free(*id3tagbuff);
	*id3tagbuff = (unsigned char *)malloc(128);
    memcpy(*id3tagbuff,tmpid3,128);
    if ( fseek (fp, *tag_offset - 128 - sizeof (T), SEEK_SET) ) return 0;
    if ( fread (&T, 1, sizeof (T), fp) != sizeof (T) ) return 0;
    // check for lyrics3 v2.00 tag
    if ( memcmp (T.ID, "LYRICS200", sizeof (T.ID)) ) return 0;
	len = Lyrics3GetNumber6 (T.Length);
	if ( fseek (fp, *tag_offset - 128 - (int)sizeof (T) - len, SEEK_SET) ) return 0;
    if ( fread  (tmp, 1, 11, fp) != 11 ) return 0;
    if ( memcmp (tmp, "LYRICSBEGIN", 11) ) return 0;
    
    taglen = 128 + Lyrics3GetNumber6(T.Length) + sizeof(T);
    
    *tag_offset -= taglen;
    if (*tagbuff != NULL) {
        free(*tagbuff);
    }
    *tagbuff = (unsigned char *)malloc(taglen);
    fseek(fp,*tag_offset,SEEK_SET);
    fread(*tagbuff,1,taglen,fp);
	*tagSize = taglen;
    return 1;
}


static unsigned long Read_LE_Uint32_unsigned ( const unsigned char* p )
{
    return ((unsigned long)p[0] <<  0) |
           ((unsigned long)p[1] <<  8) |
           ((unsigned long)p[2] << 16) |
           ((unsigned long)p[3] << 24);
}

static unsigned long Read_LE_Uint32 ( const char* p ) {return Read_LE_Uint32_unsigned((const unsigned char*)p);}


static void Write_LE_Uint32 ( char* p, const unsigned long value )
{
    p[0] = (unsigned char) (value >>  0);
    p[1] = (unsigned char) (value >>  8);
    p[2] = (unsigned char) (value >> 16);
    p[3] = (unsigned char) (value >> 24);
}

enum {
	MAX_FIELD_SIZE = 1024*1024 //treat bigger fields as errors
};

unsigned long strlen_max(const char * ptr, unsigned long max) {
	unsigned long n = 0;
	while (ptr[n] && n < max) n++;
	return n;
}

// Reads APE v1.0/2.0 tag
int ReadMP3APETag ( FILE *fp,  struct MP3GainTagInfo *info, struct APETagStruct **apeTag, long *tag_offset )
{
    unsigned long               vsize;
    unsigned long               isize;
    unsigned long               flags;
	unsigned long				remaining;
    char*                       buff;
    char*                       p;
    char*                       value;
    char*                       vp;
    char*                       end;
    struct APETagFooterStruct   T;
    unsigned long               TagLen;
    unsigned long               TagCount;
    unsigned long               origTagCount, otherFieldsCount;
    unsigned long               curFieldNum;
    unsigned long               Ver;
    char*                       name;
    int                         is_info;
	char						tmpString[10];

	if ( *tag_offset < (long)(sizeof(T)) ) return 0;
    if ( fseek(fp,*tag_offset - sizeof(T),SEEK_SET) ) return 0;
    if ( fread (&T, 1, sizeof(T), fp) != sizeof(T) ) return 0;
    if ( memcmp (T.ID, "APETAGEX", sizeof(T.ID)) ) return 0;
    Ver = Read_LE_Uint32 (T.Version);
    if ( (Ver != 1000) && (Ver != 2000) ) return 0;
    if ( (TagLen = Read_LE_Uint32 (T.Length)) < sizeof (T) ) return 0;
    if ( fseek (fp, *tag_offset - TagLen, SEEK_SET) ) return 0;
    buff = (char *)malloc (TagLen);
    if ( fread (buff, 1, TagLen - sizeof (T), fp) != (TagLen - sizeof (T)) ) {
        free (buff);
        return 0;
    }

    if (*apeTag) {
        if ((*apeTag)->otherFields)
            free((*apeTag)->otherFields);
		free(*apeTag);
    }
	*apeTag = (struct APETagStruct *)malloc(sizeof(struct APETagStruct));
	(*apeTag)->haveHeader = 0;
	(*apeTag)->otherFields = (unsigned char *)malloc(TagLen - sizeof(T));
    (*apeTag)->otherFieldsSize = 0;

	memcpy(&((*apeTag)->footer),&T,sizeof(T));

    origTagCount = TagCount = Read_LE_Uint32 (T.TagCount);
    otherFieldsCount = 0;


    end = buff + TagLen - sizeof (T);
	curFieldNum = 0;
    for ( p = buff; p < end && TagCount--; ) {
		if (end - p < 8) break;
        vsize = Read_LE_Uint32 (p); p += 4;
        flags = Read_LE_Uint32 (p); p += 4;

		remaining = (unsigned long) (end - p);
        isize = strlen_max (p, remaining);
		if (isize >= remaining || vsize > MAX_FIELD_SIZE || isize + 1 + vsize > remaining) break;

        name = (char*)malloc(isize+1);
		memcpy(name, p, isize);
		name[isize] = 0;
        value = (char*)malloc(vsize+1);
        memcpy(value, p+isize+1, vsize);
        value[vsize] = 0;

		is_info = 0;

		{
            if (!_stricmp (name, "REPLAYGAIN_TRACK_GAIN")) {
                info->haveTrackGain = !0;
                info->trackGain = atof(value);
            } else if (!_stricmp(name,"REPLAYGAIN_TRACK_PEAK")) {
                info->haveTrackPeak = !0;
                info->trackPeak = atof(value);
            } else if (!_stricmp(name,"REPLAYGAIN_ALBUM_GAIN")) {
                info->haveAlbumGain = !0;
                info->albumGain = atof(value);
            } else if (!_stricmp(name,"REPLAYGAIN_ALBUM_PEAK")) {
                info->haveAlbumPeak = !0;
                info->albumPeak = atof(value);
            } else if (!_stricmp(name,"MP3GAIN_UNDO")) {
				/* value should be something like "+003,+003,W" */
                info->haveUndo = !0;
                vp = value;
				memcpy(tmpString,vp,4);
				tmpString[4] = '\0';
                info->undoLeft = atoi(tmpString);
                vp = vp + 5; /* skip the comma, too */
				memcpy(tmpString,vp,4);
				tmpString[4] = '\0';
                info->undoRight = atoi(tmpString);
                vp = vp + 5; /* skip the comma, too */
                if ((*vp == 'w')||(*vp == 'W')) {
                    info->undoWrap = !0;
                } else {
                    info->undoWrap = 0;
                }
            } else if (!_stricmp(name,"MP3GAIN_MINMAX")) {
				/* value should be something like "001,153" */
                info->haveMinMaxGain = !0;
                vp = value;
				memcpy(tmpString,vp,3);
				tmpString[3] = '\0';
                info->minGain = atoi(tmpString);
                vp = vp + 4; /* skip the comma, too */
				memcpy(tmpString,vp,3);
				tmpString[3] = '\0';
                info->maxGain = atoi(tmpString);
            } else if (!_stricmp(name,"MP3GAIN_ALBUM_MINMAX")) {
				/* value should be something like "001,153" */
                info->haveAlbumMinMaxGain = !0;
                vp = value;
				memcpy(tmpString,vp,3);
				tmpString[3] = '\0';
                info->albumMinGain = atoi(tmpString);
                vp = vp + 4; /* skip the comma, too */
				memcpy(tmpString,vp,3);
				tmpString[3] = '\0';
                info->albumMaxGain = atoi(tmpString);
            } else {
                memcpy((*apeTag)->otherFields + (*apeTag)->otherFieldsSize, p - 8, 8 + isize + 1 + vsize);
                (*apeTag)->otherFieldsSize += 8 + isize + 1 + vsize;
                otherFieldsCount++;
            }
		}

        if ( isize > 0 && vsize > 0 ) {
            if (is_info) {
            } else {
            }
        }
        free(value);
		free(name);
        p += isize + 1 + vsize;
    }

    free (buff);
    
	*tag_offset -= TagLen;
	(*apeTag)->originalTagSize = TagLen;

    if ( Read_LE_Uint32 (T.Flags) & (1<<31) ) {  // Tag contains header
        *tag_offset -= sizeof (T);

		fseek (fp, *tag_offset, SEEK_SET);
		fread (&((*apeTag)->header),1,sizeof(T),fp);
		(*apeTag)->haveHeader = !0;
		(*apeTag)->originalTagSize += sizeof(T);
	}

    if (otherFieldsCount != origTagCount) {
         Write_LE_Uint32((*apeTag)->footer.Length, sizeof(T) + (*apeTag)->otherFieldsSize);
         Write_LE_Uint32((*apeTag)->footer.TagCount, otherFieldsCount);
         if ((*apeTag)->haveHeader) {
             Write_LE_Uint32((*apeTag)->header.Length, sizeof(T) + (*apeTag)->otherFieldsSize);
             Write_LE_Uint32((*apeTag)->header.TagCount, otherFieldsCount);
         }
    }

    return 1;
}

int truncate_file (char *filename, long truncLength) {

#ifdef WIN32
    
   int fh, result;

   /* Open a file */
    if( (fh = _open(filename, _O_RDWR))  != -1 )
    {
        if( ( result = _chsize( fh, truncLength ) ) == 0 ) {
            _close(fh);
            return 1;
        } else {
            _close(fh);
            return 0;
        }
   } else {
       return 0;
   }

#else

	int fd;

	fd = open(filename, O_RDWR);
	if (fd < 0)
		return 0;
	if (ftruncate(fd, truncLength)) {
		close(fd);
		passError( MP3GAIN_UNSPECIFED_ERROR, 3, "Could not truncate ",
			filename, "\n");
		return 0;
	}
	close(fd);

	return 1;

#endif
}


/**
 * Read gain information from an APE tag.
 *
 * Look for an APE tag at the end of the MP3 file, and extract
 * gain information from it. Any ID3v1 or Lyrics3v2 tags at the end
 * of the file are read and stored, but not processed.
 */
int ReadMP3GainAPETag (char *filename, struct MP3GainTagInfo *info, struct FileTagsStruct *fileTags) {
    FILE *fi;
    long tag_offset, offs_bk;

    fi = fopen(filename, "rb");
    if (fi == NULL)
		return 0;
	
	fseek(fi, 0, SEEK_END);
    tag_offset = ftell(fi);
	
	fileTags->lyrics3TagSize = 0;

    do {
		offs_bk = tag_offset;
		ReadMP3APETag ( fi, info, &(fileTags->apeTag), &tag_offset );
        ReadMP3Lyrics3v2Tag ( fi, &(fileTags->lyrics3tag), &(fileTags->lyrics3TagSize), &(fileTags->id31tag), &tag_offset );
		ReadMP3ID3v1Tag ( fi, &(fileTags->id31tag), &tag_offset );
	} while ( offs_bk != tag_offset );

	fileTags->tagOffset = tag_offset;

    fclose(fi);

    return 1;
};


/**
 * (Re-)Write gain information to an APEv2 tag.
 *
 * You need to have already called ReadMP3GainTag and filled in the info
 * and fileTags structures.
 */
int WriteMP3GainAPETag (char *filename, struct MP3GainTagInfo *info, struct FileTagsStruct *fileTags, int saveTimeStamp) {
	FILE *outputFile;
	unsigned long newTagLength;
	unsigned long newTagCount;
	char *newFieldData;
	char *mp3gainTagData;
	unsigned long mp3gainTagLength;
	char valueString[100];

	struct APETagFooterStruct newFooter;
	struct APETagFooterStruct newHeader;

	if (saveTimeStamp)
		fileTime(filename, storeTime);

	/* For the new tag, we'll have a footer _AND_ header (whether or not a header was in the original */
	newTagLength = sizeof(struct APETagFooterStruct) * 2;
	newTagCount = 0;
	mp3gainTagLength = 0;

	if (fileTags->apeTag) {
		/* For the new tag, we'll have the non-MP3Gain fields from the original tag */
		newTagLength += fileTags->apeTag->otherFieldsSize;
		newTagCount += Read_LE_Uint32(fileTags->apeTag->footer.TagCount);
	}

	if (info->haveAlbumGain) {
		/* 8 bytes + "REPLAYGAIN_ALBUM_GAIN" + '/0' + "+2.456789 dB" = 42 bytes */
		mp3gainTagLength += 42;
		newTagCount++;
	}
	if (info->haveAlbumPeak) {
		/* 8 bytes + "REPLAYGAIN_ALBUM_PEAK" + '/0' + "1.345678" = 38 bytes */
		mp3gainTagLength += 38;
		newTagCount++;
	}
	if (info->haveTrackGain) {
		/* 8 bytes + "REPLAYGAIN_TRACK_GAIN" + '/0' + "+2.456789 dB" = 42 bytes */
		mp3gainTagLength += 42;
		newTagCount++;
	}
	if (info->haveTrackPeak) {
		/* 8 bytes + "REPLAYGAIN_TRACK_PEAK" + '/0' + "1.345678" = 38 bytes */
		mp3gainTagLength += 38;
		newTagCount++;
	}
	if (info->haveMinMaxGain) {
		/* 8 bytes + "MP3GAIN_MINMAX" + '/0' + "123,123" = 30 bytes */
		mp3gainTagLength += 30;
		newTagCount++;
	}
	if (info->haveAlbumMinMaxGain) {
		/* 8 bytes + "MP3GAIN_ALBUM_MINMAX" + '/0' + "123,123" = 36 bytes */
		mp3gainTagLength += 36;
		newTagCount++;
	}
	if (info->haveUndo) {
		/* 8 bytes + "MP3GAIN_UNDO" + '/0' + "+123,+123,W" = 32 bytes */
		mp3gainTagLength += 32;
		newTagCount++;
	}

	newTagLength += mp3gainTagLength;

	newFieldData = (char *)malloc(newTagLength - (sizeof(newFooter) + sizeof(newHeader)));
	mp3gainTagData = newFieldData;

	if (fileTags->apeTag) {
		/* Check if the new tag will be shorter than the old tag */
		if (fileTags->apeTag->originalTagSize > newTagLength) {
			/* we'll need to truncate the file */
            if (!truncate_file(filename, fileTags->tagOffset)) {
                return 0;
            }
		}
		memcpy(&newFooter,&(fileTags->apeTag->footer),sizeof(newFooter));
		Write_LE_Uint32(newFooter.Length, newTagLength - sizeof(newHeader));
		Write_LE_Uint32(newFooter.TagCount, newTagCount);

		if (fileTags->apeTag->haveHeader) {
			memcpy(&newHeader,&(fileTags->apeTag->header), sizeof(newHeader));
			Write_LE_Uint32(newHeader.Length, newTagLength - sizeof(newFooter));
			Write_LE_Uint32(newHeader.TagCount, newTagCount);
		} else {
			memcpy(newHeader.ID,"APETAGEX",sizeof(newHeader.ID));
			Write_LE_Uint32(newHeader.Version,2000);
			Write_LE_Uint32(newHeader.Length, newTagLength - sizeof(newFooter));
			Write_LE_Uint32(newHeader.TagCount,newTagCount);
			Write_LE_Uint32(newHeader.Flags,1<<31 | 1<<29); /* tag has header, this _is_ the header */
			memset(newHeader.Reserved,0,sizeof(newHeader.Reserved));

			/* and don't forget to fix the footer so that it now shows that the tag has a header! */
			Write_LE_Uint32(newFooter.Flags, Read_LE_Uint32(newFooter.Flags) | 1<<31);
		}

		if (fileTags->apeTag->otherFieldsSize) {
			memcpy(newFieldData, fileTags->apeTag->otherFields, fileTags->apeTag->otherFieldsSize);
			mp3gainTagData += fileTags->apeTag->otherFieldsSize;
		}
	} else { /* we don't already have an APE tag, so create one from scratch */
		memcpy(newHeader.ID,"APETAGEX",sizeof(newHeader.ID));
		Write_LE_Uint32(newHeader.Version,2000);
		Write_LE_Uint32(newHeader.Length, newTagLength - sizeof(newFooter));
		Write_LE_Uint32(newHeader.TagCount,newTagCount);
		Write_LE_Uint32(newHeader.Flags,1<<31 | 1<<29); /* tag has header, this _is_ the header */
		memset(newHeader.Reserved,0,sizeof(newHeader.Reserved));

		memcpy(newFooter.ID,"APETAGEX",sizeof(newFooter.ID));
		Write_LE_Uint32(newFooter.Version,2000);
		Write_LE_Uint32(newFooter.Length, newTagLength - sizeof(newHeader));
		Write_LE_Uint32(newFooter.TagCount,newTagCount);
		Write_LE_Uint32(newFooter.Flags,1<<31); /* tag has header */
		memset(newFooter.Reserved,0,sizeof(newFooter.Reserved));
	}
	
	if (info->haveMinMaxGain) {
		/* 8 bytes + "MP3GAIN_MINMAX" + '/0' + "123,123" = 30 bytes */
		Write_LE_Uint32(mp3gainTagData,7);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "MP3GAIN_MINMAX");
		mp3gainTagData += 15;
		sprintf(mp3gainTagData,"%03d", info->minGain); /* write directly to tag buffer, because we'll replace the trailing null char anyhow */
		mp3gainTagData[3] = ',';
		mp3gainTagData += 4;
		sprintf(valueString,"%03d", info->maxGain);
		memcpy(mp3gainTagData, valueString, 3); /* DON'T write trailing null char */
		mp3gainTagData += 3;
	}
	if (info->haveAlbumMinMaxGain) {
		/* 8 bytes + "MP3GAIN_ALBUM_MINMAX" + '/0' + "123,123" = 36 bytes */
		Write_LE_Uint32(mp3gainTagData,7);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "MP3GAIN_ALBUM_MINMAX");
		mp3gainTagData += 21;
		sprintf(mp3gainTagData,"%03d", info->albumMinGain); /* write directly to tag buffer, because we'll replace the trailing null char anyhow */
		mp3gainTagData[3] = ',';
		mp3gainTagData += 4;
		sprintf(valueString,"%03d", info->albumMaxGain);
		memcpy(mp3gainTagData, valueString, 3); /* DON'T write trailing null char */
		mp3gainTagData += 3;
	}
	if (info->haveUndo) {
		/* 8 bytes + "MP3GAIN_UNDO" + '/0' + "+234,+234,W" = 32 bytes */
		Write_LE_Uint32(mp3gainTagData,11);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "MP3GAIN_UNDO");
		mp3gainTagData += 13;
		sprintf(mp3gainTagData,"%+04d", info->undoLeft); /* write directly to tag buffer, because we'll replace the trailing null char anyhow */
		mp3gainTagData[4] = ',';
		mp3gainTagData += 5;
		sprintf(mp3gainTagData,"%+04d", info->undoRight); /* write directly to tag buffer, because we'll replace the trailing null char anyhow */
		mp3gainTagData[4] = ',';
		mp3gainTagData += 5;
		if (info->undoWrap) {
			*mp3gainTagData = 'W';
		} else {
			*mp3gainTagData = 'N';
		}
		mp3gainTagData++;
	}
	if (info->haveTrackGain) {
		/* 8 bytes + "REPLAYGAIN_TRACK_GAIN" + '/0' + "+2.456789 dB" = 42 bytes */
		Write_LE_Uint32(mp3gainTagData,12);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "REPLAYGAIN_TRACK_GAIN");
		mp3gainTagData += 22;
		sprintf(valueString,"%-+9.6f", info->trackGain);
		memcpy(mp3gainTagData, valueString, 9);
		mp3gainTagData += 9;
		memcpy(mp3gainTagData, " dB", 3);
		mp3gainTagData += 3;
	}
	if (info->haveTrackPeak) {
		/* 8 bytes + "REPLAYGAIN_TRACK_PEAK" + '/0' + "1.345678" = 38 bytes */
		Write_LE_Uint32(mp3gainTagData,8);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "REPLAYGAIN_TRACK_PEAK");
		mp3gainTagData += 22;
		sprintf(valueString,"%-8.6f", info->trackPeak);
		memcpy(mp3gainTagData, valueString, 8);
		mp3gainTagData += 8;
	}
	if (info->haveAlbumGain) {
		/* 8 bytes + "REPLAYGAIN_ALBUM_GAIN" + '/0' + "+2.456789 dB" = 42 bytes */
		Write_LE_Uint32(mp3gainTagData,12);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "REPLAYGAIN_ALBUM_GAIN");
		mp3gainTagData += 22;
		sprintf(valueString,"%-+9.6f", info->albumGain);
		memcpy(mp3gainTagData, valueString, 9);
		mp3gainTagData += 9;
		memcpy(mp3gainTagData, " dB", 3);
		mp3gainTagData += 3;
	}
	if (info->haveAlbumPeak) {
		/* 8 bytes + "REPLAYGAIN_ALBUM_PEAK" + '/0' + "1.345678" = 38 bytes */
		Write_LE_Uint32(mp3gainTagData,8);
		mp3gainTagData += 4;
		Write_LE_Uint32(mp3gainTagData,0);
		mp3gainTagData += 4;
		strcpy(mp3gainTagData, "REPLAYGAIN_ALBUM_PEAK");
		mp3gainTagData += 22;
		sprintf(valueString,"%-8.6f", info->albumPeak);
		memcpy(mp3gainTagData, valueString, 8);
		mp3gainTagData += 8;
	}


	outputFile = fopen(filename,"r+b");
	if (outputFile == NULL) {
		  passError( MP3GAIN_UNSPECIFED_ERROR, 3,
			  "\nCan't open ", filename, " for modifying\n");
		return 0;
	}
	fseek(outputFile,fileTags->tagOffset,SEEK_SET);
	if (newTagCount > 0) { /* write APE tag */
		fwrite(&newHeader,1,sizeof(newHeader),outputFile);
		fwrite(newFieldData, 1, newTagLength - (sizeof(newFooter) + sizeof(newHeader)), outputFile);
		fwrite(&newFooter,1,sizeof(newFooter),outputFile);
	}
	if (fileTags->lyrics3TagSize > 0) {
		fwrite(fileTags->lyrics3tag, 1, fileTags->lyrics3TagSize, outputFile);
	}
    else if (fileTags->id31tag) { //by definition, Lyrics3 tag includes id3 tag,
		fwrite(fileTags->id31tag, 1, 128, outputFile); //so only write id3 tag alone if
    }                                                  //no Lyrics3 tag

	fclose(outputFile);
	
	if (saveTimeStamp)
		fileTime(filename,setStoredTime);

	free(newFieldData);
    return 1;
};


/**
 * Remove gain information from the APE tag.
 */
int RemoveMP3GainAPETag (char *filename, int saveTimeStamp) {
	struct MP3GainTagInfo info;
	struct FileTagsStruct fileTags;

	info.dirty = 0;

	info.haveAlbumGain = 0;
	info.haveAlbumPeak = 0;
	info.haveTrackGain = 0;
	info.haveTrackPeak = 0;
	info.haveMinMaxGain = 0;
	info.haveAlbumMinMaxGain = 0;
	info.haveUndo = 0;
    
    fileTags.apeTag = NULL;
    fileTags.id31tag = NULL;
    fileTags.lyrics3tag = NULL;
    fileTags.lyrics3TagSize = 0;

	ReadMP3GainAPETag(filename, &info, &fileTags);


	/* if any MP3Gain tags exist, then we're going to change the tag */
	if (info.haveAlbumGain || info.haveAlbumPeak || info.haveTrackGain || info.haveTrackPeak || info.haveMinMaxGain || info.haveAlbumMinMaxGain || info.haveUndo)
		info.dirty = !0;

	info.haveAlbumGain = 0;
	info.haveAlbumPeak = 0;
	info.haveTrackGain = 0;
	info.haveTrackPeak = 0;
	info.haveMinMaxGain = 0;
	info.haveAlbumMinMaxGain = 0;
	info.haveUndo = 0;

	if (info.dirty)
		WriteMP3GainAPETag(filename, &info, &fileTags, saveTimeStamp);

    return 1;
};
