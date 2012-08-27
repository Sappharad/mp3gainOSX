/* $Id: interface.c,v 1.5 2005/01/18 15:56:45 snelg Exp $ */

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "common.h"
#include "interface.h"
#include "tabinit.h"
#include "layer3.h"
#include "VbrTag.h"

#ifdef USE_LAYER_1
	#include "layer1.h"
#endif

#ifdef USE_LAYER_2
	#include "layer2.h"
#endif

#ifdef WITH_DMALLOC
#include <dmalloc.h>
#endif


BOOL InitMP3( PMPSTR mp) 
{
	memset(mp,0,sizeof(MPSTR));

	mp->framesize = 0;
        mp->num_frames = 0;
        mp->vbr_header=0;
	mp->header_parsed=0;
	mp->side_parsed=0;
	mp->data_parsed=0;
	mp->free_format=0;
	mp->old_free_format=0;
	mp->ssize = 0;
	mp->dsize=0;
	mp->fsizeold = -1;
	mp->bsize = 0;
	mp->head = mp->tail = NULL;
	mp->fr.single = -1;
	mp->bsnum = 0;
	wordpointer = mp->bsspace[mp->bsnum] + 512;
	mp->synth_bo = 1;
	mp->sync_bitstream = 1;

	make_decode_tables(32767);

	init_layer3(SBLIMIT);

#ifdef USE_LAYER_2
	init_layer2();
#endif

	return !0;
}

void ExitMP3( PMPSTR mp)
{
	struct buf *b,*bn;
	
	b = mp->tail;
	while(b) {
		free(b->pnt);
		bn = b->next;
		free(b);
		b = bn;
	}
}

static struct buf *addbuf( PMPSTR mp, unsigned char *ibuf,int size)
{
	struct buf *nbuf;

	nbuf = (struct buf*) malloc( sizeof(struct buf) );
	if(!nbuf) {
		fprintf(stderr,"Out of memory!\n");
		return NULL;
	}
	nbuf->pnt = (unsigned char*) malloc((size_t)size);
	if(!nbuf->pnt) {
		free(nbuf);
		return NULL;
	}
	nbuf->size = size;
	memcpy(nbuf->pnt,ibuf,(size_t)size);
	nbuf->next = NULL;
	nbuf->prev = mp->head;
	nbuf->pos = 0;

	if(!mp->tail) {
		mp->tail = nbuf;
	}
	else {
	  mp->head->next = nbuf;
	}

	mp->head = nbuf;
	mp->bsize += size;

	return nbuf;
}

void remove_buf(PMPSTR mp)
{
  struct buf *buff = mp->tail;
  
  mp->tail = buff->next;
  if(mp->tail)
    mp->tail->prev = NULL;
  else {
    mp->tail = mp->head = NULL;
  }
  
  free(buff->pnt);
  free(buff);

}

static int read_buf_byte(PMPSTR mp)
{
	unsigned int b;

	int pos;

	
	pos = mp->tail->pos;
	while(pos >= mp->tail->size) {
	        remove_buf(mp);
		if(!mp->tail) {
			fprintf(stderr,"Fatal error! tried to read past mp buffer\n");
            fclose(stdout);
            fclose(stderr);
			exit(1);
		}
		pos = mp->tail->pos;
	}

	b = mp->tail->pnt[pos];
	mp->bsize--;
	mp->tail->pos++;
	

	return b;
}



static void read_head(PMPSTR mp)
{
	unsigned long head;

	head = read_buf_byte(mp);
	head <<= 8;
	head |= read_buf_byte(mp);
	head <<= 8;
	head |= read_buf_byte(mp);
	head <<= 8;
	head |= read_buf_byte(mp);

	mp->header = head;
}






void copy_mp(PMPSTR mp,int size,unsigned char *ptr) 
{
  int len = 0;

  while(len < size) {
    int nlen;
    int blen = mp->tail->size - mp->tail->pos;
    if( (size - len) <= blen) {
      nlen = size-len;
    }
    else {
      nlen = blen;
    }
    memcpy(ptr+len,mp->tail->pnt+mp->tail->pos,(size_t)nlen);
    len += nlen;
    mp->tail->pos += nlen;
    mp->bsize -= nlen;
    if(mp->tail->pos == mp->tail->size) {
      remove_buf(mp);
    }
  }
}

char VBRTag[5] = "Xing";

static int ExtractI4(unsigned char *buf)
{
	int x;
	/* big endian extract */
	x = buf[0];
	x <<= 8;
	x |= buf[1];
	x <<= 8;
	x |= buf[2];
	x <<= 8;
	x |= buf[3];
	return x;
}

const int  bitrate_table    [3] [16] = {
    { 0,  8, 16, 24, 32, 40, 48, 56,  64,  80,  96, 112, 128, 144, 160, -1 },
    { 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, -1 },
    { 0,  8, 16, 24, 32, 40, 48, 56,  64,  80,  96, 112, 128, 144, 160, -1 },
};

const int  samplerate_table [3]  [4] = { 
    { 22050, 24000, 16000, -1 },
    { 44100, 48000, 32000, -1 },
    { 11025, 12000,  8000, -1 },
};

int GetVbrTag(VBRTAGDATA *pTagData,  unsigned char *buf)
{
	int			i, head_flags;
	int			h_bitrate,h_id, h_mode, h_sr_index;

	/* get Vbr header data */
	pTagData->flags = 0;

	/* get selected MPEG header data */
	h_id       = (buf[1] >> 3) & 1;
	h_sr_index = (buf[2] >> 2) & 3;
	h_mode     = (buf[3] >> 6) & 3;
        h_bitrate  = ((buf[2]>>4)&0xf);
	h_bitrate = bitrate_table[h_id][h_bitrate];


	/*  determine offset of header */
	if( h_id )
	{
                /* mpeg1 */
		if( h_mode != 3 )	buf+=(32+4);
		else				buf+=(17+4);
	}
	else
	{
                /* mpeg2 */
		if( h_mode != 3 ) buf+=(17+4);
		else              buf+=(9+4);
	}

	if( buf[0] != VBRTag[0] ) return 0;    /* fail */
	if( buf[1] != VBRTag[1] ) return 0;    /* header not found*/
	if( buf[2] != VBRTag[2] ) return 0;
	if( buf[3] != VBRTag[3] ) return 0;

	buf+=4;

	pTagData->h_id = h_id;
	pTagData->samprate = samplerate_table[h_id][h_sr_index];

	if( h_id == 0 )
		pTagData->samprate >>= 1;

	head_flags = pTagData->flags = ExtractI4(buf); buf+=4;      /* get flags */

	if( head_flags & FRAMES_FLAG )
	{
		pTagData->frames   = ExtractI4(buf); buf+=4;
	}

	if( head_flags & BYTES_FLAG )
	{
		pTagData->bytes = ExtractI4(buf); buf+=4;
	}

	if( head_flags & TOC_FLAG )
	{
		if( pTagData->toc != NULL )
		{
			for(i=0;i<NUMTOCENTRIES;i++)
				pTagData->toc[i] = buf[i];
		}
		buf+=NUMTOCENTRIES;
	}

	pTagData->vbr_scale = -1;

	if( head_flags & VBR_SCALE_FLAG )
	{
		pTagData->vbr_scale = ExtractI4(buf); buf+=4;
	}

	pTagData->headersize = 
	  ((h_id+1)*72000*h_bitrate) / pTagData->samprate;


#ifdef DEBUG_VBRTAG
	DEBUGF("\n\n********************* VBR TAG INFO *****************\n");
	DEBUGF("tag         :%s\n",VBRTag);
	DEBUGF("head_flags  :%d\n",head_flags);
	DEBUGF("bytes       :%d\n",pTagData->bytes);
	DEBUGF("frames      :%d\n",pTagData->frames);
	DEBUGF("VBR Scale   :%d\n",pTagData->vbr_scale);
	DEBUGF("toc:\n");
	if( pTagData->toc != NULL )
	{
		for(i=0;i<NUMTOCENTRIES;i++)
		{
			if( (i%10) == 0 ) DEBUGF("\n");
			DEBUGF(" %3d", (int)(pTagData->toc[i]));
		}
	}
	DEBUGF("\n***************** END OF VBR TAG INFO ***************\n");
#endif
	return 1;       /* success */
}



// traverse mp data structure without changing it
// (just like sync_buffer)
// pull out 48 bytes
// call vbr header check code from LAME
// if we find a header, parse it and also compute the VBR header size
// if no header, do nothing.
//
// bytes = number of bytes before MPEG header.  skip this many bytes
// before starting to read
// return value: number of bytes in VBR header, including syncword
int check_vbr_header(PMPSTR mp,int bytes)
{
  int i,pos;
  struct buf *ibuf=mp->tail;
  unsigned char xing[48];
  VBRTAGDATA pTagData;

  pos = ibuf->pos;
  // skip to valid header
  for (i=0; i<bytes; ++i) {
    while(pos >= ibuf->size) {
      ibuf  = ibuf->next;
      pos = ibuf->pos;
      if(!ibuf) 	return -1; /* fatal error */
    }
    ++pos;
  }
  // now read 48 bytes
  for (i=0; i<48; ++i) {
    while(pos >= ibuf->size) {
      ibuf  = ibuf->next;
      pos = ibuf->pos;
      if(!ibuf) 	return -1; /* fatal error */
    }
    xing[i] = ibuf->pnt[pos];
    ++pos;
  }

  /* check first 48 bytes for Xing header */
  mp->vbr_header = GetVbrTag(&pTagData,xing);
  if (mp->vbr_header) {
    mp->num_frames=pTagData.frames;
    // fprintf(stderr,"\rmpglib: Xing VBR header dectected.  MP3 file has %i frames\n", pTagData.frames);
    return pTagData.headersize;
  }
  return 0;
}







int sync_buffer(PMPSTR mp,int free_match) 
{
  /* traverse mp structure without modifing pointers, looking
   * for a frame valid header.
   * if free_format, valid header must also have the same
   * samplerate.   
   * return number of bytes in mp, before the header
   * return -1 if header is not found
   */
  unsigned int b[4]={0,0,0,0};
  int i,h,pos;
  struct buf *buff=mp->tail;

  pos = buff->pos;
  for (i=0; i<mp->bsize; i++) {
    /* get 4 bytes */
    
    b[0]=b[1]; b[1]=b[2]; b[2]=b[3];
    while(pos >= buff->size) {
      buff  = buff->next;
      pos = buff->pos;
      if(!buff) {
	return -1;
	/* not enough data to read 4 bytes */
      }
    }
    b[3] = buff->pnt[pos];
    ++pos;

    if (i>=3) {
        struct frame *fr = &mp->fr;
	unsigned long head;

	head = b[0];
	head <<= 8;
	head |= b[1];
	head <<= 8;
	head |= b[2];
	head <<= 8;
	head |= b[3];
	h = head_check(head,fr->lay);

	if (h && free_match) {
	  /* just to be even more thorough, match the sample rate */
	  int mode,stereo,sampling_frequency,mpeg25,lsf;

	  if( head & (1<<20) ) {
	    lsf = (head & (1<<19)) ? 0x0 : 0x1;
	    mpeg25 = 0;
	  }
	  else {
	    lsf = 1;
	    mpeg25 = 1;
	  }

	  mode      = ((head>>6)&0x3);
	  stereo    = (mode == MPG_MD_MONO) ? 1 : 2;

	  if(mpeg25) 
	    sampling_frequency = 6 + ((head>>10)&0x3);
	  else
	    sampling_frequency = ((head>>10)&0x3) + (lsf*3);
	  h = ((stereo==fr->stereo) && (lsf==fr->lsf) && (mpeg25==fr->mpeg25) && 
                 (sampling_frequency == fr->sampling_frequency));
	}

	if (h) {
	  return i-3;
	}
    }
  }
  return -1;
}





int decodeMP3( PMPSTR mp,unsigned char *in,int isize,int *done)
{
	int i,iret,bits,bytes;

	if(in) {
		if(addbuf(mp,in,isize) == NULL) {
			return MP3_ERR;
		}
	}


	/* First decode header */
	if(!mp->header_parsed) {

	    if (mp->fsizeold==-1 || mp->sync_bitstream) {
	        int vbrbytes;
		mp->sync_bitstream=0;

	        /* This is the very first call.   sync with anything */
		/* bytes= number of bytes before header */
	        bytes=sync_buffer(mp,0); 

	        /* now look for Xing VBR header */
		if (mp->bsize >= bytes+48 ) {
		    /* vbrbytes = number of bytes in entire vbr header */
		    vbrbytes=check_vbr_header(mp,bytes);
		} else {
		    /* not enough data to look for Xing header */
		    return MP3_NEED_MORE;
		}

		if (mp->vbr_header) {
		    /* do we have enough data to parse entire Xing header? */
		    if (bytes+vbrbytes > mp->bsize) return MP3_NEED_MORE;
		    
		    /* read in Xing header.  Buffer data in case it
		     * is used by a non zero main_data_begin for the next
		     * frame, but otherwise dont decode Xing header */
		    for (i=0; i<vbrbytes+bytes; ++i) read_buf_byte(mp);
		    /* now we need to find another syncword */
		    /* just return and make user send in more data */
		    return MP3_NEED_MORE;
		}
            }else{
	        /* match channels, samplerate, etc, when syncing */
                bytes=sync_buffer(mp,1);
	    }

	    if (bytes<0) return MP3_NEED_MORE;
	    if (bytes>0) {
		/* there were some extra bytes in front of header.
		 * bitstream problem, but we are now resynced 
		 * should try to buffer previous data in case new
		 * frame has nonzero main_data_begin, but we need
		 * to make sure we do not overflow buffer
		 */
		int size;
//		fprintf(stderr,"bitstream problem: resyncing...\n");
		mp->old_free_format=0;
                mp->sync_bitstream=1;
		
		/* skip some bytes, buffer the rest */
		size = (int) (wordpointer - (mp->bsspace[mp->bsnum]+512));
		
		if (size > MAXFRAMESIZE) {
		    /* wordpointer buffer is trashed.  probably cant recover, but try anyway */
//		    fprintf(stderr,"mpglib: wordpointer trashed.  size=%i (%i)  bytes=%i \n",
//			    size,MAXFRAMESIZE,bytes);		  
		    size=0;
		    wordpointer = mp->bsspace[mp->bsnum]+512;
		}
		
		/* buffer contains 'size' data right now 
		   we want to add 'bytes' worth of data, but do not 
		   exceed MAXFRAMESIZE, so we through away 'i' bytes */
		i = (size+bytes)-MAXFRAMESIZE;
		for (; i>0; --i) {
		    --bytes;
		    read_buf_byte(mp);
		}
		
		copy_mp(mp,bytes,wordpointer);
		mp->fsizeold += bytes;
	    }
	    
	    read_head(mp);
	    decode_header(&mp->fr,mp->header);
	    mp->header_parsed=1;
	    mp->framesize = mp->fr.framesize;
	    mp->free_format = (mp->framesize==0);
	    
	    if(mp->fr.lsf)
		mp->ssize = (mp->fr.stereo == 1) ? 9 : 17;
	    else
		mp->ssize = (mp->fr.stereo == 1) ? 17 : 32;
	    if (mp->fr.error_protection) 
		mp->ssize += 2;
	    
	    mp->bsnum = 1-mp->bsnum; /* toggle buffer */
	    wordpointer = mp->bsspace[mp->bsnum] + 512;
	    bitindex = 0;
	    
	    /* for very first header, never parse rest of data */
	    if (mp->fsizeold==-1)
		return MP3_NEED_MORE;
	}
	
	/* now decode side information */
	if (!mp->side_parsed) {

		/* Layer 3 only */
		if (mp->fr.lay==3)
		{
                if (mp->bsize < mp->ssize) 
		  return MP3_NEED_MORE;

		copy_mp(mp,mp->ssize,wordpointer);

		if(mp->fr.error_protection)
		  getbits(16);
		bits=do_layer3_sideinfo(&mp->fr);
		if (bits == -32767) {
			ExitMP3(mp);
			InitMP3(mp);
			return MP3_ERR;
		}
		/* bits = actual number of bits needed to parse this frame */
		/* can be negative, if all bits needed are in the reservoir */
		if (bits<0) bits=0;

		/* read just as many bytes as necessary before decoding */
		mp->dsize = (bits+7)/8;

		/* this will force mpglib to read entire frame before decoding */
		/* mp->dsize= mp->framesize - mp->ssize;*/

		}

		else
		{
			/* Layers 1 and 2 */

			/* check if there is enough input data */
			if(mp->fr.framesize > mp->bsize)
				return MP3_NEED_MORE;

			/* takes care that the right amount of data is copied into wordpointer */
			mp->dsize=mp->fr.framesize;
			mp->ssize=0;
		}

		mp->side_parsed=1;
	}

	/* now decode main data */
	iret=MP3_NEED_MORE;
	if (!mp->data_parsed ) {
	        if(mp->dsize > mp->bsize) {
				return MP3_NEED_MORE;
		}

		copy_mp(mp,mp->dsize,wordpointer);

		*done = 0;

		//do_layer3(&mp->fr,(unsigned char *) out,done);
		iret=MP3_OK;
		switch (mp->fr.lay)
		{
#ifdef USE_LAYER_1
			case 1:
				if(mp->fr.error_protection)
					getbits(16);

				do_layer1(mp,(unsigned char *) out,done);
			break;
#endif
#ifdef USE_LAYER_2
			case 2:
				if(mp->fr.error_protection)
					getbits(16);

				do_layer2(mp,(unsigned char *) out,done);
			break;
#endif
			case 3:
				if (do_layer3(mp,done)) {
					iret = MP3_ERR;
				}
			break;
			default:
				fprintf(stderr,"invalid layer %d\n",mp->fr.lay);
		}

		wordpointer = mp->bsspace[mp->bsnum] + 512 + mp->ssize + mp->dsize;

		mp->data_parsed=1;
	}


	/* remaining bits are ancillary data, or reservoir for next frame 
	 * If free format, scan stream looking for next frame to determine
	 * mp->framesize */
	if (mp->free_format) {
	  if (mp->old_free_format) {
	    /* free format.  bitrate must not vary */
	    mp->framesize=mp->fsizeold_nopadding + (mp->fr.padding);
	  }else{
	    bytes=sync_buffer(mp,1);
	    if (bytes<0) return iret;
	    mp->framesize = bytes + mp->ssize+mp->dsize;
	    mp->fsizeold_nopadding= mp->framesize - mp->fr.padding;
	    /*
	    fprintf(stderr,"freeformat bitstream:  estimated bitrate=%ikbs  \n",
	        8*(4+mp->framesize)*freqs[mp->fr.sampling_frequency]/
		    (1000*576*(2-mp->fr.lsf)));
	    */
	  }
	}

	/* buffer the ancillary data and reservoir for next frame */
	bytes = mp->framesize-(mp->ssize+mp->dsize);
	if (bytes > mp->bsize) {
	  return iret;
	}

	if (bytes>0) {
	  int size;
	  copy_mp(mp,bytes,wordpointer);
	  wordpointer += bytes;

	  size = (int) (wordpointer - (mp->bsspace[mp->bsnum]+512));
	  if (size > MAXFRAMESIZE) {
	    fprintf(stderr,"fatal error.  MAXFRAMESIZE not large enough.\n");
	  }

	}

	/* the above frame is completey parsed.  start looking for next frame */
	mp->fsizeold = mp->framesize;
	mp->old_free_format = mp->free_format;
	mp->framesize =0;
	mp->header_parsed=0;
	mp->side_parsed=0;
	mp->data_parsed=0;

	return iret;
}

	

