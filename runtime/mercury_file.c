/*
** Copyright (C) 2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** This module contains the implementation of Mercury streams using
** C `FILE *' streams.
*/

#include "mercury_file.h"
#include "mercury_std.h"	/* for MR_assert */

#ifndef MR_NEW_MERCURYFILE_STRUCT
  void
  MR_mercuryfile_init(FILE *file, int line_number, MercuryFile *mf)
  {
	MR_file(*mf)	    = file;
	MR_line_number(*mf) = line_number;
  }

#else

  void
  MR_mercuryfile_init(FILE *file, int line_number, MercuryFile *mf)
  {
	mf->stream_type	= MR_FILE_STREAM;
	mf->stream_info.file	= file;
	mf->line_number	= line_number;

	mf->close		= MR_close;
	mf->read		= MR_read;
	mf->write		= MR_write;

	mf->flush		= MR_flush;
	mf->ungetc		= MR_ungetch;
	mf->getc		= MR_getch;
	mf->vprintf		= MR_vfprintf;
	mf->putc		= MR_putch;
  }

  int
  MR_getch(MR_StreamInfo *info) 
  {
	MR_assert(info != NULL);
	return getc(info->file);	  
  }

  int
  MR_ungetch(MR_StreamInfo *info, int ch)
  {
	int res;
	MR_assert(info != NULL);		
	res = ungetc(ch, info->file);
	if (res == EOF) {
		mercury_io_error(NULL, "io__putback_char: ungetc failed");
	}
	return (int) res;
  }

  int
  MR_putch(MR_StreamInfo *info, int ch)
  {
	MR_assert(info != NULL);
	return putc(ch, info->file);
  }

  int
  MR_close(MR_StreamInfo *info)
  {
	MR_assert(info != NULL);				      
	return fclose(info->file);
  }
  
  int
  MR_flush(MR_StreamInfo *info)
  {
	MR_assert(info != NULL);				       
	return fflush(info->file);
  }
  
  int
  MR_vfprintf(MR_StreamInfo *info, const char *format, va_list ap)
  {
	MR_assert(info != NULL);
	MR_assert(format != NULL);

	return vfprintf(info->file, format, ap);
  }
  
  int
  MR_read(MR_StreamInfo *info, void *buffer, size_t size)
  { 
	int rc;							       
	MR_assert(info != NULL);				
	rc = fread(buffer, sizeof(unsigned char), size, info->file);

		/* Handle error/eof special cases */
	if ( (rc < size) &&  feof(info->file) ) {
		/* nothing to do */;
	} else if ( ferror(info->file) ) {
		rc = -1;
	}

	return rc;
  }

  int
  MR_write(MR_StreamInfo *info, const void *buffer, size_t size)
  {
	int rc;							       

	MR_assert(info != NULL);
	rc = fwrite(buffer, sizeof(unsigned char), size, info->file);

	return (rc < size ? -1 : rc);
  }
#endif /* MR_NEW_MERCURYFILE_STRUCT */
