/**
 * Handling of Replay Gain information in ID3v2 tags.
 *
 * We store Replay Gain data in RVA2 frames inside the ID3v2.4 tag.
 * Album and track gain are written as two separate frames.
 * We use the RVA2 frame as follows:
 *
 * Identification string:  either "track" or "album";
 * Channel number:         always 1 (master volume);
 * Volume adjustment:      recommended gain relative to 89 dB standard;
 * Bits representing peak: always 16;
 * Peak volume:            max absolute sample value relative to full scale
 *
 * The meaning of the RVA2 peak volume field is not specified in ID3v2.4.
 * We follow the interpretation of QuodLibet/mutagen: Peak volume is the
 * maximum absolute sample value relative to full scale, before application
 * of the volume adjustment, stored as an unsigned fixed point value with
 * 1 integer bit and (peakbits-1) fractional bits.
 *
 * In addition to standard Replay Gain data, we also store mp3gain-specific
 * fields in TXXX frames. The description string of such frames starts with
 * "MP3GAIN_". These frames are only needed when mp3gain updates the encoded
 * audio volume in MP3 stream (-r and -a command line options).
 *
 * We read tag data in ID3v2.2, ID3v2.3 or ID3v2.4 format, from either
 * the beginning or the end of the file. Extended tag headers are ignored
 * and removed; compressed frames are ignored but preserved. No workarounds
 * are attempted for invalid ID3v2.4 tags.
 *
 * When writing/updating tag data, we always write a single ID3v2.4 tag
 * at the beginning of the file, fully unsynchronized. If the original
 * file had an ID3v2.2 or ID3v2.3 tag, it is upgraded to ID3v2.4. If the
 * original file had only an appended tag, it is moved to the beginning of
 * the file. If the original file contained multiple tags, we update only
 * the first tag and ignore the rest (this is bad, but it's probably a
 * rare case). If the original file had only an ID3v1 tag, it is copied
 * to a new ID3v2 tag and the ID3v1 tag is left as it was.
 *
 * See: http://www.id3.org/id3v2.4.0-structure
 *      http://www.id3.org/id3v2.4.0-frames
 */


#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "apetag.h"
#include "id3tag.h"
#include "mp3gain.h"


#ifdef WIN32
#define strcasecmp(x,y) _stricmp(x,y)
#endif

#define DBG(x)
/*#define DBG(x) (printf x)*/

#define TAGFL_UNSYNC		(0x80)
#define TAGFL_EXTHDR		(0x40)
#define TAGFL_EXPR			(0x20)
#define TAGFL_FOOTER		(0x10)
#define FRAMEFL_BAD			(0x00f0)
#define FRAMEFL_TAGALTER	(0x4000)
#define FRAMEFL_GROUP		(0x0040)
#define FRAMEFL_COMPR		(0x0008)
#define FRAMEFL_CRYPT		(0x0004)
#define FRAMEFL_UNSYNC		(0x0002)
#define FRAMEFL_DLEN		(0x0001)
#define SYNCSAFE_INT_BAD	(0xffffffff)


struct ID3v2TagStruct {
	unsigned long offset;				/* offset of tag in file */
	unsigned long length;				/* total length of ID3v2 tag, including header/footer */
	unsigned int version;				/* ID3v2 version */
	unsigned int flags;					/* tag flags */
	struct ID3v2FrameStruct *frames;	/* linked list of frames */
};

struct ID3v2FrameStruct {
	struct ID3v2FrameStruct *next;		/* pointer to next frame */
	char frameid[4];					/* frame ID */
	unsigned int flags;					/* frame flags */
	unsigned long len;					/* length of frame, excluding header */
	unsigned long hskip;				/* length of flag parameters */
	unsigned char *data;				/* pointer to data, excluding header */
};

struct upgrade_id3v22_struct {
	char id_v22[3];
	char id_new[4];
};

static const struct upgrade_id3v22_struct upgrade_id3v22_table[] = {
	{ "BUF", "RBUF" }, { "CNT", "PCNT" },
	{ "COM", "COMM" }, { "CRA", "AENC" },
	{ "ETC", "ETCO" }, { "EQU", "EQUA" },
	{ "GEO", "GEOB" }, { "IPL", "IPLS" },
	{ "LNK", "LINK" }, { "MCI", "MCDI" },
	{ "MLL", "MLLT" }, { "PIC", "APIC" /* NOTE: incompatible format */ },
	{ "POP", "POPM" }, { "REV", "RVRB" },
	{ "RVA", "RVAD" }, { "SLT", "SYLT" },
	{ "STC", "SYTC" }, { "TAL", "TALB" },
	{ "TBP", "TBPM" }, { "TCM", "TCOM" },
	{ "TCO", "TCON" }, { "TCR", "TCOP" },
	{ "TDA", "TDAT" }, { "TDY", "TDLY" },
	{ "TEN", "TENC" }, { "TFT", "TFLT" },
	{ "TIM", "TIME" }, { "TKE", "TKEY" },
	{ "TLA", "TLAN" }, { "TLE", "TLEN" },
	{ "TMT", "TMED" }, { "TOA", "TOPE" },
	{ "TOF", "TOFN" }, { "TOL", "TOLY" },
	{ "TOR", "TORY" }, { "TOT", "TOAL" },
	{ "TP1", "TPE1" }, { "TP2", "TPE2" },
	{ "TP3", "TPE3" }, { "TP4", "TPE4" },
	{ "TPA", "TPOS" }, { "TPB", "TPUB" },
	{ "TRC", "TSRC" }, { "TRD", "TRDA" },
	{ "TRK", "TRCK" }, { "TSI", "TSIZ" },
	{ "TSS", "TSSE" }, { "TT1", "TIT1" },
	{ "TT2", "TIT2" }, { "TT3", "TIT3" },
	{ "TXT", "TEXT" }, { "TXX", "TXXX" },
	{ "TYE", "TYER" }, { "UFI", "UFID" },
	{ "ULT", "USLT" }, { "WAF", "WOAF" },
	{ "WAR", "WOAR" }, { "WAS", "WOAS" },
	{ "WCM", "WCOM" }, { "WCP", "WCOP" },
	{ "WPB", "WPUB" }, { "WXX", "WXXX" },
	{ "\0\0\0", "\0\0\0\0" } };


/**
 * Decode a 4-byte unsigned integer.
 */
static __inline unsigned long id3_get_int32(const unsigned char *p)
{
	return (p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}


/**
 * Decode a 4-byte unsigned synchsafe integer.
 */
static __inline unsigned long id3_get_syncsafe_int(const unsigned char *p)
{
	if ((p[0] | p[1] | p[2] | p[3]) & 0x80)
		return SYNCSAFE_INT_BAD;
	return (p[0] << 21) | (p[1] << 14) | (p[2] << 7) | p[3];
}


/**
 * Write a 4-byte unsigned synchsafe integer.
 */
static __inline void id3_put_syncsafe_int(unsigned char *p, unsigned long i)
{
	p[0] = (i >> 21) & 0x7f;
	p[1] = (i >> 14) & 0x7f;
	p[2] = (i >>  7) & 0x7f;
	p[3] = i & 0x7f;
}


/**
 * Decode srclen bytes of unsynchronized data from src into dest.
 * Return the number of bytes written into dest.
 *
 * The buffer pointed to by dest must be large enough to hold the decoded data.
 * The decoded data will never be longer than the unsynchronized data.
 * Decoding may be performed in-place by specifying dest equal to src.
 *
 * If dest == NULL, decoded data are not stored but the decoded length is
 * still computed and returned.
 */
static unsigned long id3_get_unsync_data(unsigned char *dest, const unsigned char *src, unsigned long srclen)
{
	unsigned long k = 0, i;
	for (i = 0; i < srclen; i++) {
		if (dest)
			dest[k] = src[i];
		k++;
		if (src[i] == 0xff && i + 1 < srclen && src[i+1] == 0x00)
			i++;
	}
	return k;
}


/**
 * Encode srclen bytes of data from src, writing the unsynchronized version
 * into dest. Return the number of bytes written into dest.
 *
 * The buffer pointed to by dest must be large enough to hold the
 * unsynchronized data.
 *
 * If dest == NULL, unsynchronized data are not stored but the unsynchronized
 * length is still computed and returned.
 *
 * If the returned length is equal to srclen, unsynchronization is not
 * needed for these data.
 */
static unsigned long id3_put_unsync_data(unsigned char *dest, const unsigned char *src, unsigned long srclen)
{
	unsigned long k = 0, i;
	for (i = 0; i < srclen; i++) {
		if (dest)
			dest[k] = src[i];
		k++;
		if (src[i] == 0xff && (i + 1 == srclen || src[i+1] == 0x00 || (src[i+1] & 0xe0) == 0xe0)) {
			if (dest)
				dest[k] = 0x00;
			k++;
		}
	}
	return k;
}


/**
 * Release memory associated with a chain of frame structures.
 */
static void id3_release_frames(struct ID3v2FrameStruct *frame)
{
	struct ID3v2FrameStruct *tframe;
	while (frame) {
		tframe = frame;
		frame = frame->next;
		free(tframe->data);
		free(tframe);
	}
}


/**
 * Construct an ID3v2 frame according to specified format and parameters.
 *
 * The format string contains one character per field in the frame:
 *   's'  stores a string without null-termination (expects const char *)
 *   'b'  stores a single byte (expects unsigned int)
 *   'h'  stores a 16-bit big-endian integer (expects unsigned int)
 *
 * Return a newly allocated ID3v2FrameStruct, or NULL if the format
 * is invalid.
 */
static struct ID3v2FrameStruct * id3_make_frame(const char *frameid, const char *format, ...)
{
	va_list ap;
	struct ID3v2FrameStruct *frame;
	unsigned long j, k;
	unsigned int i;
	const char *p, *s;

	va_start(ap, format);
	k = 0;
	for (p = format; *p; p++) {
		switch (*p) {
			case 's':	/* string */
				s = va_arg(ap, const char *);
				k += strlen(s);
				break;
			case 'b':	/* byte */
				i = va_arg(ap, unsigned int);
				k += 1;
				break;
			case 'h':	/* 16-bit integer */
				i = va_arg(ap, unsigned int);
				k += 2;
				break;
			default:
				va_end(ap);
				return NULL;
		}
	}
	va_end(ap);

	frame = malloc(sizeof(struct ID3v2FrameStruct));
	frame->next = NULL;
	strncpy(frame->frameid, frameid, 4);
	frame->flags = 0;
	frame->len = k;
	frame->hskip = 0;
	frame->data = malloc(k);

	va_start(ap, format);
	k = 0;
	for (p = format; *p; p++) {
		switch (*p) {
			case 's':	/* string */
				s = va_arg(ap, const char *);
				j = strlen(s);
				memcpy(frame->data + k, s, j);
				k += j;
				break;
			case 'b':	/* byte */
				i = va_arg(ap, unsigned int);
				frame->data[k] = i;
				k += 1;
				break;
			case 'h':	/* 16-bit integer */
				i = va_arg(ap, unsigned int);
				frame->data[k] = (i >> 8) & 0xff;
				frame->data[k+1] = i & 0xff;
				k += 2;
				break;
			default:
				va_end(ap);
				return NULL;
		}
	}
	va_end(ap);

	return frame;
}


/**
 * Decode an RVA2 frame (only track/album gain, only master channel).
 *
 * Store gain information in the info structure, unless info == NULL.
 * Return 1 if the frame is an RVA2 frame with track/album gain, 0 otherwise.
 */
static int id3_decode_rva2_frame(const struct ID3v2FrameStruct *frame, struct MP3GainTagInfo *info)
{
	unsigned long p;
	int is_album_gain, channel, peakbits;
	double gain, peak;

	/* Ignore non-RVA2 frames. */
	if (memcmp(frame->frameid, "RVA2", 4) != 0)
		return 0;

	p = frame->hskip;

	/* Check identification string; we understand only "track" and "album". */
	if (p + 6 <= frame->len &&
	    (memcmp(frame->data + p, "track\0", 6) == 0 ||
	     memcmp(frame->data + p, "TRACK\0", 6) == 0)) {
		is_album_gain = 0; 
		p += 6;
	} else if (p + 6 <= frame->len &&
	           (memcmp(frame->data + p, "album\0", 6) == 0 ||
	            memcmp(frame->data + p, "ALBUM\0", 6) == 0)) {
		is_album_gain = 1;
		p += 6;
	} else {
		return 0;
	}

	/* Process per-channel data. */
	while (p + 4 <= frame->len) {
		/*
		 *  p+0 :       channel number
		 *  p+1, p+2 :  16-bit signed BE int = adjustment * 512
		 *  p+3 :       nr of bits representing peak
		 *  p+4 ... :   unsigned multibyte BE int = peak sample * 2**(peakbits-1)
		 */
		channel = frame->data[p];
		gain = (double)(((signed char)(frame->data[p+1]) << 8) | frame->data[p+2]) / 512.0;
		peakbits = frame->data[p+3];
		if (p + 4 + (peakbits + 7) / 8 > frame->len)
			break;
		peak = 0;
		if (peakbits > 0)  peak += (double)(frame->data[p+4]);
		if (peakbits > 8)  peak += (double)(frame->data[p+5]) / 256.0;
		if (peakbits > 16) peak += (double)(frame->data[p+6]) / 65536.0;
		if (peakbits > 0)  peak = peak / (double)(1 << ((peakbits - 1) & 7));
		p += 4 + (peakbits + 7) / 8;
		if (channel == 1) { /* channel == master volume channel */
			if (info) {
				if (is_album_gain) {
					info->haveAlbumGain = 1;
					info->albumGain = gain;
					info->haveAlbumPeak = (peakbits > 0);
					info->albumPeak = peak;
				} else {
					info->haveTrackGain = 1;
					info->trackGain = gain;
					info->haveTrackPeak = (peakbits > 0);
					info->trackPeak = peak;
				}
			}
		}
	}

	return 1;
}


/**
 * Create an RVA2 frame, track or album gain, master channel.
 * Return a newly allocated ID3v2FrameStruct.
 */
static struct ID3v2FrameStruct * id3_make_rva2_frame(int is_album_gain, double gain, int have_peak, double peak)
{
	const char *ident;
	int g;
	unsigned int p;
	/*
	 * identification:    string = "track" or "album"
	 * channel type:      byte   = 1 (master volume)
	 * volume adjustment: int16  = gain * 512
	 * peak bits:         byte   = 16 (or 0 if no peak information)
	 * peak:              uint16 = peak * 32768
	 */
	ident = (is_album_gain) ? "album" : "track";
	g = (gain <= -64) ? -32768 :
	    (gain >=  64) ? 32767 :
	    (int)(gain * 512);
	if (g < -32768) g = -32768;
	if (g >  32767) g = 32767;
	if (have_peak) {
		p = (peak <= 0) ? 0 :
		    (peak >= 2) ? 65535 :
		    (unsigned int)(peak * 32768);
		if (p > 65535) p = 65535;
		return id3_make_frame("RVA2", "sbbhbh", ident, 0, 1, g, 16, p);
	} else {
		return id3_make_frame("RVA2", "sbbhb", ident, 0, 1, g, 0);
	}
}


/**
 * Decode a mp3gain-specific TXXX frame, either "MP3GAIN_UNDO" or
 * "MP3GAIN_MINMAX" or "MP3GAIN_ALBUM_MINMAX".
 *
 * Store gain information in the info structure, unless info == NULL.
 * Return 1 if the frame is a mp3gain-specific TXXX frame, 0 otherwise.
 */
static int id3_decode_mp3gain_frame(const struct ID3v2FrameStruct *frame, struct MP3GainTagInfo *info)
{
	unsigned long p, k;
	char buf[64];
	int f1, f2;
	char f3;

	/* Ignore non-TXXX frames. */
	if (memcmp(frame->frameid, "TXXX", 4) != 0)
		return 0;

	p = frame->hskip;

	/* Check text encoding; we understand only 0 (ISO-8859-1) and 3 (UTF-8). */
	if (p >= frame->len || (frame->data[p] != 0 && frame->data[p] != 3))
		return 0;
	p++;

	/* Copy character data to temporary buffer. */
	k = (frame->len - p + 1 < sizeof(buf)) ? (frame->len - p) : (sizeof(buf) - 2);
	memcpy(buf, frame->data + p, k);
	buf[k] = '\0';		/* terminate the value string */
	buf[k+1] = '\0';	/* ensure buf contains two terminated strings, even for invalid frame data */

	/* Check identification string. */
	if (strcasecmp(buf, "MP3GAIN_UNDO") == 0) {
		/* value should be something like "+003,+003,W" */
		if (sscanf(buf + strlen(buf) + 1, "%d,%d,%c", &f1, &f2, &f3) == 3 &&
		    info != NULL) {
			info->haveUndo = 1;
			info->undoLeft = f1;
			info->undoRight = f2;
			info->undoWrap = (f3 == 'w' || f3 == 'W');
		}
		return 1;
	} else if (strcasecmp(buf, "MP3GAIN_MINMAX") == 0) {
		/* value should be something like "001,153" */
		if (sscanf(buf + strlen(buf) + 1, "%d,%d", &f1, &f2) == 2 &&
		    info != NULL) {
			info->haveMinMaxGain = 1;
			info->minGain = f1;
			info->maxGain = f2;
		}
		return 1;
	} else if (strcasecmp(buf, "MP3GAIN_ALBUM_MINMAX") == 0) {
		/* value should be something like "001,153" */
		if (sscanf(buf + strlen(buf) + 1, "%d,%d", &f1, &f2) == 2 &&
		    info != NULL) {
			info->haveAlbumMinMaxGain = 1;
			info->albumMinGain = f1;
			info->albumMaxGain = f2;
		}
		return 1;
	}

	return 0;
}


/**
 * Read an ID3v2 tag from the current position in the MP3 file.
 *
 * Return 1 on success, 0 if no tag is found, or a negative error code
 * if the tag can not be processed.
 */
static int id3_parse_v2_tag(FILE *f, struct ID3v2TagStruct *tag)
{
	unsigned char buf[12], frameid[4];
	unsigned int fflags;
	unsigned long dlen, flen, fhskip, p, k;
	unsigned char *tagdata;
	struct ID3v2FrameStruct *frame, **pframe;

	/* Read header */
	tag->offset = ftell(f);
	if (fread(buf, 1, 10, f) != 10)
		return 0;

	/* Check 'ID3' signature. */
	if (memcmp(buf, "ID3", 3) != 0)
		return 0;

	DBG(("DEBUG: Found ID3v2 tag at offset %lu\n", tag->offset));

	/* Check version and flags. */
	switch (buf[3]) {
		case 2:	/* ID3v2.2 */
			if (buf[5] & (~(TAGFL_UNSYNC)))
				return M3G_ERR_TAGFORMAT;	/* unknown flags */
			break;
		case 3: /* ID3v2.3 */
			if (buf[5] & (~(TAGFL_UNSYNC | TAGFL_EXTHDR | TAGFL_EXPR)))
				return M3G_ERR_TAGFORMAT;	/* unknown flags */
			break;
		case 4: /* ID3v2.4 */
			if (buf[5] & (~(TAGFL_UNSYNC | TAGFL_EXTHDR | TAGFL_EXPR | TAGFL_FOOTER)))
				return M3G_ERR_TAGFORMAT;	/* unknown flags */
			break;
		default:
			return M3G_ERR_TAGFORMAT;		/* unknown version */
	}

	/* Check length. */
	dlen = id3_get_syncsafe_int(buf + 6);
	if (dlen == SYNCSAFE_INT_BAD)
		return M3G_ERR_TAGFORMAT;

	/* Fill tag structure. */
	tag->flags   = buf[5];
	tag->version = (buf[3] << 8) | buf[4];
	tag->length  = 10 + dlen + ((tag->flags & TAGFL_FOOTER) ? 10 : 0);
	tag->frames  = NULL;

	DBG(("  version=%04x length=%lu flags=%02x\n", tag->version, tag->length, tag->flags));

	/* Read rest of the tag. */
	tagdata = malloc(dlen);
	if (fread(tagdata, 1, dlen, f) != dlen)
		goto badtag;

	/* If this is an unsynced v2.2 or v2.3 tag, decode it now. */
	if ((tag->version >> 8) != 4 && (tag->flags & TAGFL_UNSYNC) != 0) {
		dlen = id3_get_unsync_data(tagdata, tagdata, dlen);
	}

	/* Skip extended header. */
	p = 0;
	if ((tag->flags & TAGFL_EXTHDR) != 0) {
		DBG(("  skip extended header\n"));
		if (p + 6 > dlen)
			goto badtag;
		if ((tag->version >> 8) == 4) {
			/* Skip ID3v2.4 extended header */
			k = id3_get_syncsafe_int(tagdata + p);
			if (k == SYNCSAFE_INT_BAD || k > dlen)
				goto badtag;
			p += k;
		} else if ((tag->version >> 8) == 3) {
			/* Skip ID3v2.3 extended header */
			k = id3_get_int32(tagdata + p);
			if (k > dlen)
				goto badtag;
			p += 4 + k;
		}
	}

	/* Scan frames. */
	pframe = &(tag->frames);
	while (p < dlen && tagdata[p] != '\0') {

		/* Decode frame header. */
		switch (tag->version >> 8) {

			case 2: /* ID3v2.2 */
				if (p + 5 > dlen)
					goto badtag;
				memset(frameid, 0, 4);
				for (k = 0; upgrade_id3v22_table[k].id_new[0]; k++) {
					if (memcmp(tagdata + p, upgrade_id3v22_table[k].id_v22, 3) == 0) {
						memcpy(frameid, upgrade_id3v22_table[k].id_new, 4);
						break;
					}
				}
				flen   = (tagdata[p+3] << 16) | (tagdata[p+4] << 8) | tagdata[p+5];
				fflags = 0;
				if (flen > dlen)
					goto badtag;
				p += 6;
				break;

			case 3: /* ID3v2.3 */
				if (p + 10 > dlen)
					goto badtag;
				memcpy(frameid, tagdata + p, 4);
				flen   = id3_get_int32(tagdata + p + 4);
				fflags = (tagdata[p+8] << 7) & 0xff00;
				if (tagdata[p+9] & 0x80) fflags |= FRAMEFL_COMPR | FRAMEFL_DLEN;
				if (tagdata[p+9] & 0x40) fflags |= FRAMEFL_CRYPT;
				if (tagdata[p+9] & 0x20) fflags |= FRAMEFL_GROUP;
				if (tagdata[p+9] & 0x1f) fflags |= FRAMEFL_BAD;
				if (flen > dlen)
					goto badtag;
				p += 10;
				break;

			case 4: /* ID3v2.4 */
				if (p + 10 > dlen)
					goto badtag;
				memcpy(frameid, tagdata + p, 4);
				flen   = id3_get_syncsafe_int(tagdata + p + 4);
				fflags = (tagdata[p+8] << 8) | tagdata[p+9];
				if (flen == SYNCSAFE_INT_BAD || flen > dlen)
					goto badtag;
				p += 10;
				break;

			default: /* unreachable */
				goto badtag;
		}

		if (p + flen > dlen)
			goto badtag;

		DBG(("  got frameid=%.4s fflags=%04x\n", frameid, fflags));

		/* Drop unsupported frame types. */
		if (frameid[0] == '\0' ||
		    memcmp(frameid, "RVAD", 4) == 0 ||
		    memcmp(frameid, "RGAD", 4) == 0 ||
		    memcmp(frameid, "XRVA", 4) == 0) {
			DBG(("  drop unsupported frame\n"));
			p += flen;
			continue;
		}

		/* Drop v2.3 frames which we can not upgrade. */
		if ((tag->version >> 8) == 3 && (fflags & (FRAMEFL_CRYPT | FRAMEFL_BAD)) != 0) {
			DBG(("  drop non-upgradable frame\n"));
			p += flen;
			continue;
		}

		/* Drop frames that are too short for their flags. */
		fhskip = (fflags & FRAMEFL_GROUP ? 1 : 0) +
		         (fflags & FRAMEFL_CRYPT ? 1 : 0) +
		         (fflags & FRAMEFL_DLEN  ? 4 : 0);
		if (fhskip > flen) {
			DBG(("  drop short frame\n"));
			p += flen;
			continue;
		}

		/* Drop v2.2 PIC frames that are too short. */
		if ((tag->version >> 8) == 2 && memcmp(frameid, "APIC", 4) == 0 && flen < 6) {
			DBG(("  drop short PIC frame\n"));
			p += flen;
			continue;
		}

		/* Rename TYER (Year) to TDRC (Recording time) */
		if (memcmp(frameid, "TYER", 4) == 0)
			memcpy(frameid, "TDRC", 4);

		/* Drop frames that want to be dropped on tag alteration. */
		if (fflags & FRAMEFL_TAGALTER) {
			DBG(("  drop FRAMEFL_TAGALTER frame\n"));
			p += flen;
			continue;
		}

		/* Allocate frame structure. */
		frame = malloc(sizeof(struct ID3v2FrameStruct));
		frame->next = NULL;
		memcpy(frame->frameid, frameid, 4);
		frame->flags = fflags;
		frame->hskip = fhskip;
		*pframe = frame;
		pframe = &(frame->next);

		/* Copy frame data. */
		if ((tag->version >> 8) == 4 && (fflags & FRAMEFL_UNSYNC) != 0) {
			/* This frame is unsynchronized; decode it now. */
			frame->data = malloc(flen);
			k = id3_get_unsync_data(frame->data, tagdata + p, flen);
			frame->len = k;
			p += flen;
		} else if ((tag->version >> 8) == 2 && memcmp(frameid, "APIC", 4) == 0) {
			/* APIC frame format differs from PIC frame format */
			frame->data = malloc(flen + 12);
			frame->data[0] = tagdata[p];
			k = 1;
			if (memcmp(tagdata + p + 1, "PNG", 3) == 0) {
				memcpy(frame->data + k, "image/png", strlen("image/png") + 1);
				k += strlen("image/png") + 1;
			} else if (memcmp(tagdata + p + 1, "JPG", 3) == 0) {
				memcpy(frame->data + k, "image/jpeg", strlen("image/jpeg") + 1);
				k += strlen("image/jpeg") + 1;
			} else if (tagdata[p+1] == '\0') {
				memcpy(frame->data + k, tagdata + p + 1, 3);
				frame->data[k+3] = '\0';
				k += 4;
			}
			memcpy(frame->data + k, tagdata + p + 4, flen - 4);
			frame->len = k + flen - 4;
			p += flen;
		} else {
			/* Normal case, just copy the data. */
			frame->data = malloc(flen);
			memcpy(frame->data, tagdata + p, flen);
			frame->len = flen;
			p += flen;
		}

		/* Reorder flag parameters of upgraded v2.3 frames. */
		if ((tag->version >> 8) == 3 && (fflags & FRAMEFL_DLEN) != 0) {
			k = id3_get_int32(frame->data);
			if (fflags & FRAMEFL_GROUP) {
				frame->data[0] = frame->data[4];
				id3_put_syncsafe_int(frame->data + 1, k);
			} else {
				id3_put_syncsafe_int(frame->data, k);
			}
		}

	}

	if (p > dlen)
		goto badtag;

	free(tagdata);
	return 1;

badtag:
	free(tagdata);
	id3_release_frames(tag->frames);
	return M3G_ERR_TAGFORMAT;
}


/**
 * Write an ID3v2 tag at the current position in the MP3 file.
 *
 * Tags are always written in ID3v2.4 format.
 * Tags are always written completely unsynchronized,
 * without extended header, padded up to an integer multiple of 2 KB.
 * We don't write a tag footer (not supported by QuodLibet).
 *
 * Return 1 on success, 0 if the tag contains no frames,
 * or a negative error code.
 */
static int id3_write_tag(FILE *f, struct ID3v2TagStruct *tag)
{
	unsigned long dlen, p, k;
	unsigned char *tagdata;
	struct ID3v2FrameStruct *frame;

	DBG(("DEBUG: Writing ID3v2 tag\n"));

	/* Do not write a tag with zero frames. */
	if (tag->frames == NULL)
		return 0;

	/* Compute raw total length of tag. */
	dlen = 10;				/* tag header */
	for (frame = tag->frames; frame; frame = frame->next) {
		dlen += 10;
		dlen += id3_put_unsync_data(NULL, frame->data, frame->len);
	}
	dlen = (dlen + 2047) & (~2047);		/* padding */

	DBG(("  length=%lu\n", dlen));

	/* Allocate buffer and fill with zeros. */
	tagdata = calloc(dlen, sizeof(unsigned char));

	/* Prepare tag header. */
	tagdata[0] = 'I';
	tagdata[1] = 'D';
	tagdata[2] = '3';
	tagdata[3] = 4;
	tagdata[4] = 0;
	tagdata[5] = TAGFL_UNSYNC | (tag->flags & TAGFL_EXPR);
	id3_put_syncsafe_int(tagdata + 6, dlen - 10);
	p = 10;

	/* Prepare frames. */
	for (frame = tag->frames; frame; frame = frame->next) {
		unsigned long fflags = frame->flags & (~FRAMEFL_UNSYNC);
		memcpy(tagdata + p, frame->frameid, 4);
		k = id3_put_unsync_data(tagdata + p + 10, frame->data, frame->len);
		id3_put_syncsafe_int(tagdata + p + 4, k);
		if (k != frame->len) fflags |= FRAMEFL_UNSYNC;
		tagdata[p+8] = (fflags >> 8) & 0xff;
		tagdata[p+9] = fflags & 0xff;
		p += 10 + k;
		DBG(("  write frameid=%.4s length=%lu\n", frame->frameid, 10 + k));
	}

	/* Write the whole thing. */
	if (fwrite(tagdata, 1, dlen, f) != dlen) {
		free(tagdata);
		return M3G_ERR_WRITE;
	}

	free(tagdata);
	return 1;
}


/**
 * Read an ID3v1 tag from the current position in the MP3 file.
 *
 * Return 1 on success, 0 if no tag is found.
 */
static int id3_parse_v1_tag(FILE *f, struct ID3v2TagStruct *tag)
{
	unsigned char buf[128];
	char sbuf[32];

	struct ID3v2FrameStruct **pframe;

	/* Read tag */
	tag->offset = ftell(f);
	if (fread(buf, 1, 128, f) != 128)
		return 0;

	/* Check 'TAG' signature. */
	if (memcmp(buf, "TAG", 3) != 0)
		return 0;

	DBG(("DEBUG: Found ID3v1 tag at offset %lu\n", tag->offset));

	/* Convert ID3v1 data to ID3v2.4 */
	tag->length = 128;
	tag->version = 0;
	tag->flags = 0;
	tag->frames = NULL;

	pframe = &(tag->frames);

	/* Add title field (offset 3, len 30). */
	if (buf[3] != '\0') {
		memcpy(sbuf, buf + 3, 30);
		sbuf[30] = '\0';
		*pframe = id3_make_frame("TIT2", "bs", 0, sbuf);
		pframe = &((*pframe)->next);
	}

	/* Add artist field (offset 33, len 30). */
	if (buf[33] != '\0') {
		memcpy(sbuf, buf + 33, 30);
		sbuf[30] = '\0';
		*pframe = id3_make_frame("TPE1", "bs", 0, sbuf);
		pframe = &((*pframe)->next);
	}

	/* Add album field (offset 63, len 30). */
	if (buf[63] != '\0') {
		memcpy(sbuf, buf + 63, 30);
		sbuf[30] = '\0';
		*pframe = id3_make_frame("TALB", "bs", 0, sbuf);
		pframe = &((*pframe)->next);
	}

	/* Add release year (offset 93, len 4). */
	if (buf[93] >= '0' && buf[93] <= '9' &&
	    buf[94] >= '0' && buf[94] <= '9' &&
	    buf[95] >= '0' && buf[95] <= '9' &&
	    buf[96] >= '0' && buf[96] <= '9') {
		memcpy(sbuf, buf + 93, 4);
		sbuf[4] = '\0';
		*pframe = id3_make_frame("TDRC", "bs", 0, sbuf);
		pframe = &((*pframe)->next);
	}

	/* Add comment (offset 97, len 30). */
	if (buf[97] != '\0') {
		memcpy(sbuf, buf + 97, 30);
		sbuf[30] = '\0';
		/* assume ISO-8859-1, unknown language, no description */
		*pframe = id3_make_frame("COMM", "bssbs", 0, "XXX", "", 0, sbuf);
		pframe = &((*pframe)->next);
	}

	/* Add track number (offset 126, len 1). */
	if (buf[125] == '\0' && buf[126] != 0) {
		sprintf(sbuf, "%u", buf[126]);
		*pframe = id3_make_frame("TRCK", "bs", 0, sbuf);
		pframe = &((*pframe)->next);
	}

	return 1;
}


/**
 * Search for an ID3v2 tag at the beginning and end of the file.
 * If no ID3v2 tag is found, search for an ID3v1 tag at the end
 * of the file.
 *
 * Return 1 on success, 0 if no tag is found, or a negative error code
 * if the tag can not be processed.
 */
static int id3_search_tag(FILE *f, struct ID3v2TagStruct *tag)
{
	unsigned char buf[32];
	unsigned long pos, k, id3v1_pos = 0;
	int j, ret;

	/* Look for ID3v2 at the beginning of the file. */
	fseek(f, 0, SEEK_SET);
	ret = id3_parse_v2_tag(f, tag);

	if (ret == 0) {
		/* Look for ID3v2 at the end of the file. */

		fseek(f, 0, SEEK_END);
		pos = ftell(f);

		while (pos > 128) {

			/* Test for ID3v2 footer */
			fseek(f, pos - 10, SEEK_SET);
			if (fread(buf, 1, 10, f) != 10)
				return M3G_ERR_READ;
			if (memcmp(buf, "3DI", 3) == 0 &&
			    buf[3] == 4 &&
			    ((buf[6] | buf[7] | buf[8] | buf[9]) & 0x80) == 0) {
				/* Parse ID3v2.4 tag */
				k = id3_get_syncsafe_int(buf + 6);
				if (20 + k < pos) {
					pos -= 20 + k;
					fseek(f, pos, SEEK_SET);
					ret = id3_parse_v2_tag(f, tag);
					break;
				}
			}

			/* Test for ID3v1/Lyrics3v2 tag */
			fseek(f, pos - 128, SEEK_SET);
			if (fread(buf, 1, 3, f) != 3)
				return M3G_ERR_READ;
			if (memcmp(buf, "TAG", 3) == 0) {
				/* Skip over ID3v1 tag and continue */
				pos -= 128;
				DBG(("DEBUG: Skipping ID3v1 tag at offset %lu\n", pos));
				id3v1_pos = pos;
				/* Test for Lyrics3v2 tag */
				if (pos > 26) {
					fseek(f, pos - 15, SEEK_SET);
					if (fread(buf, 1, 15, f) != 15)
						return M3G_ERR_READ;
					if (memcmp(buf + 6, "LYRICS200", 9) == 0) {
						/* Skip over Lyrics tag */
						k = 0;
						for (j = 0; j < 6; j++) {
							if (buf[j] < '0' || buf[j] > '9') {
								k = 0;
								break;
							}
							k = 10 * k + (buf[j] - '0');
						}
						if (k >= 11 && k + 15 < pos) {
							pos -= k + 15;
							DBG(("DEBUG: Skipping Lyrics3v2 tag at offset %lu\n", pos));
						}
					}
				}
				continue;
			}

			/* Test for APE tag */
			fseek(f, pos - 32, SEEK_SET);
			if (fread(buf, 1, 32, f) != 32)
				return M3G_ERR_READ;
			if (memcmp(buf, "APETAGEX", 8) == 0) {
				/* Skip over APE tag and continue */
				k = buf[12] | (buf[13] << 8) | (buf[14] << 16) | (buf[15] << 24); /* tag length */
				if (buf[23] & 0x80)
					k += 32; /* tag header present */
				if (k >= 32 && k < pos) {
					pos -= k;
					DBG(("DEBUG: Skipping APE tag at offset %lu\n", pos));
					continue;
				}
			}

			/* No more tags to skip. */
			break;

		}
		
	}

	if (ret == 0 && id3v1_pos != 0) {
		/* Read ID3v1 at the end of the file. */
		fseek(f, id3v1_pos, SEEK_SET);
		ret = id3_parse_v1_tag(f, tag);
	}

	return ret;
}


/**
 * Seek to offset in inf and copy count bytes to the current
 * position in outf. If count == -1, copy until the end of the file.
 *
 * Return 1 on success, otherwise a negative error code.
 */
static int id3_copy_data(FILE *inf, FILE *outf, long offset, long count)
{
	const long bufsize = 65536;
	char *buf;
	size_t k;
	int ret;

	ret = 1;
	buf = malloc(bufsize);

	if (fseek(inf, offset, SEEK_SET))
		ret = M3G_ERR_READ;

	while (ret == 1 && count != 0) {
		k = (count > 0 && count < bufsize) ? count : bufsize;
		k = fread(buf, 1, k, inf);
		if (k == 0) {
			if (!feof(inf) || count > 0)
				ret = M3G_ERR_READ;
			break;
		}
		if (fwrite(buf, 1, k, outf) != k) {
			ret = M3G_ERR_WRITE;
			break;
		}
		if (count > 0)
			count -= k;
	}

	free(buf);
	return ret;
}


/**
 * Read gain information from an ID3v2 tag.
 */
int ReadMP3GainID3Tag(char *filename, struct MP3GainTagInfo *info)
{
	FILE *f;
	struct ID3v2TagStruct tag;
	struct ID3v2FrameStruct *frame;
	int ret;

	f = fopen(filename, "rb");
	if (f == NULL) {
		passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Could not open ", filename, "\n");
		return M3G_ERR_FILEOPEN;
	}

	ret = id3_search_tag(f, &tag);
	fclose(f);

	if (ret == M3G_ERR_READ) {
		passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Error reading ", filename, "\n");
	}

	if (ret == 1) {
		/* Got the tag; extract gain information from the RVA2/TXXX frames. */
		frame = tag.frames;
		while (frame) {
			id3_decode_rva2_frame(frame, info);
			id3_decode_mp3gain_frame(frame, info);
			frame = frame->next;
		}
		id3_release_frames(tag.frames);
	}

	return ret;
}


/**
 * (Re-)Write gain information to an ID3v2 tag.
 *
 * Writes or updates an ID3v2.4 tag at the beginning of the file.
 * If the file does not yet contain an ID3v2 tag, a new tag is created,
 * copying basic fields from an ID3v1 tag if present.
 * If the file contains an ID3v2.2 or ID3v2.3 tag, it is rewritten as ID3v2.4.
 *
 * Since modifications are made at the beginning of the file, the entire
 * file is rewritten to a temporary file and then moved in place of the
 * old file.
 */
int WriteMP3GainID3Tag(char *filename, struct MP3GainTagInfo *info, int saveTimeStamp)
{
	char sbuf[32];
	char *tmpfilename;
	FILE *f, *outf;
	struct ID3v2TagStruct tag;
	struct ID3v2FrameStruct *frame, **pframe;
	int ret, need_update;

	if (saveTimeStamp)
		fileTime(filename, storeTime);

	f = fopen(filename, "rb");
	if (f == NULL) {
		passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Could not open ", filename, "\n");
		return M3G_ERR_FILEOPEN;
	}
	ret = id3_search_tag(f, &tag);

	switch (ret) {
		case M3G_ERR_READ:
			passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Error reading ", filename, "\n");
			break;
		case M3G_ERR_TAGFORMAT:
			passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Unsupported ID3v2 tag in ", filename, "\n");
			break;
	}

	if (ret < 0) {
		/* Error. */
		fclose(f);
		return ret;
	}

	if (ret == 0) {
		/* No ID3v2 or ID3v1 tag found in the file; create a new tag. */
		tag.offset = 0;
		tag.length = 0;
		tag.version = 0;
		tag.flags = 0;
		tag.frames = NULL;
	}

	/* Kill existing replaygain frames. */
	need_update = 0;
	pframe = &(tag.frames);
	while ((frame = *pframe)) {
		if (id3_decode_rva2_frame(frame, NULL) == 1 ||
		    id3_decode_mp3gain_frame(frame, NULL) == 1) {
			/* This is a ReplayGain frame; kill it. */
			need_update = 1;
			*pframe = frame->next;
			free(frame->data);
			free(frame);
		} else {
			pframe = &((*pframe)->next);
		}
	}

	/* Append new replaygain frames. */
	if (info->haveTrackGain) {
		need_update = 1;
		frame = id3_make_rva2_frame(0, info->trackGain, info->haveTrackPeak, info->trackPeak);
		*pframe = frame;
		pframe = &(frame->next);
	}
	if (info->haveAlbumGain) {
		need_update = 1;
		frame = id3_make_rva2_frame(1, info->albumGain, info->haveAlbumPeak, info->albumPeak);
		*pframe = frame;
		pframe = &(frame->next);
	}

	/* Append mp3gain-specific frames. */
	if (info->haveMinMaxGain) {
		need_update = 1;
		sprintf(sbuf, "%03d,%03d", info->minGain, info->maxGain);
		frame = id3_make_frame("TXXX", "bsbs", 0, "MP3GAIN_MINMAX", 0, sbuf);
		*pframe = frame;
		pframe = &(frame->next);
	}
	if (info->haveAlbumMinMaxGain) {
		need_update = 1;
		sprintf(sbuf, "%03d,%03d", info->albumMinGain, info->albumMaxGain);
		frame = id3_make_frame("TXXX", "bsbs", 0, "MP3GAIN_ALBUM_MINMAX", 0, sbuf);
		*pframe = frame;
		pframe = &(frame->next);
	}
	if (info->haveUndo) {
		need_update = 1;
		sprintf(sbuf, "%+04d,%+04d,%c", info->undoLeft, info->undoRight, info->undoWrap ? 'W' : 'N');
		frame = id3_make_frame("TXXX", "bsbs", 0, "MP3GAIN_UNDO", 0, sbuf);
		*pframe = frame;
		pframe = &(frame->next);
	}

	if (!need_update) {
		/* No need to change MP3 file. */
		fclose(f);
		id3_release_frames(tag.frames);
		return 0;
	}

	/* Create temporary file. */
	tmpfilename = malloc(strlen(filename) + 5);
	strcpy(tmpfilename, filename);
	strcat(tmpfilename, ".TMP");
	outf = fopen(tmpfilename, "wb");
	if (outf == NULL) {
		passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Can not create temporary file ", tmpfilename, "\n");
		fclose(f);
		free(tmpfilename);
		id3_release_frames(tag.frames);
		return M3G_ERR_CANT_MAKE_TMP;
	}

	/* Write new ID3v2 tag. */
	ret = id3_write_tag(outf, &tag);

	/* Write rest of MP3 file. */
	if (ret >= 0) {
		if (tag.version == 0) {
			/* The original file has no ID3v2 tag; copy everything. */
			ret = id3_copy_data(f, outf, 0, -1);
		} else {
			/* The original file has an ID3v2 tag; copy everything
			   except the original tag. */
			ret = id3_copy_data(f, outf, 0, tag.offset);
			if (ret >= 0)
				ret = id3_copy_data(f, outf, tag.offset + tag.length, -1);
		}
	}

	fclose(outf);
	fclose(f);
	id3_release_frames(tag.frames);

	switch (ret) {
		case M3G_ERR_READ:
			passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Error reading ", filename, "\n");
			break;
		case M3G_ERR_WRITE:
			passError(MP3GAIN_UNSPECIFED_ERROR, 3, "Error writing ", tmpfilename, "\n");
			break;
	}

	if (ret < 0) {
		/* Delete temp file after error. */
		remove(tmpfilename);
		free(tmpfilename);
		return ret;
	}

	/* Replace original file. */
#ifdef WIN32
	/* "rename" function in WIN32 does _not_ replace existing destination file, so
	   we have to manually remove it first */
	if (remove(filename) != 0) {
		passError(MP3GAIN_UNSPECIFED_ERROR, 5, "Can not rename ", tmpfilename, " to ", filename, "\n");
		ret = M3G_ERR_RENAME_TMP;
		/* Do NOT remove the temp file itself, just in case the "remove(filename)" function
		   only _temporarily_ failed, and the original file will disappear soon, such as when
		   all handles on the file are closed. If it does disappear and we also
		   delete the tmp file, then the file is completely gone... */
		free(tmpfilename);
	}
#endif

	ret = 1;
	if (rename(tmpfilename, filename)) {
		remove(tmpfilename);
		passError(MP3GAIN_UNSPECIFED_ERROR, 5, "Can not rename ", tmpfilename, " to ", filename, "\n");
		ret = M3G_ERR_RENAME_TMP;
	} else {
		if (saveTimeStamp)
			fileTime(filename, setStoredTime);
	}

	free(tmpfilename);

	return ret;
}


/**
 * Remove gain information from the ID3v2 tag.
 * Return 1 on success, 0 if no changes are needed, or a negative error code.
 */
int RemoveMP3GainID3Tag(char *filename, int saveTimeStamp)
{
	struct MP3GainTagInfo info;

	info.haveAlbumGain = 0;
	info.haveAlbumPeak = 0;
	info.haveTrackGain = 0;
	info.haveTrackPeak = 0;
	info.haveMinMaxGain = 0;
	info.haveAlbumMinMaxGain = 0;
	info.haveUndo = 0;

	return WriteMP3GainID3Tag(filename, &info, saveTimeStamp);
}

