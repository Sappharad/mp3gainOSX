#
# Quick 'n dirty unix Makefile
#
# Mike Oliphant (oliphant@gtk.org)
#

CC?= gcc

CFLAGS+= -Wall -DHAVE_MEMCPY

# all known MS Windows OS define the ComSpec environment variable
ifdef ComSpec
ifndef OSTYPE
OSTYPE = win
endif
EXE_EXT = .exe
else
EXE_EXT =
endif

ifneq ($(OSTYPE),beos)
INSTALL_PATH= /usr/local/bin
else
INSTALL_PATH= $(HOME)/config/bin
endif

# BeOS doesn't have libm (it's all in libroot)
ifneq ($(OSTYPE),beos)
LIBS= -lm
else
# BeOS: without this it wants to use bcopy() :^)
CFLAGS+= -DHAVE_MEMCPY
endif

ifeq ($(OSTYPE),win)
# gnu windows resource compiler
WINDRES = windres
endif

OBJS=	mp3gain.o apetag.o id3tag.o gain_analysis.o rg_error.o \
	mpglibDBL/common.o mpglibDBL/dct64_i386.o \
	mpglibDBL/decode_i386.o mpglibDBL/interface.o \
	mpglibDBL/layer3.o mpglibDBL/tabinit.o
ifeq ($(OSTYPE),win)
RC_OBJ = VerInfo.o
endif

all: mp3gain

$(RC_OBJ): 
	$(WINDRES) $(RC_OBJ:.o=.rc) $(RC_OBJ)

mp3gain: $(RC_OBJ) $(OBJS)
	$(CC) $(LDFLAGS) -o mp3gain $(OBJS) $(RC_OBJ) $(LIBS)
ifeq ($(OSTYPE),beos)
	mimeset -f mp3gain$(EXE_EXT)
endif

install: mp3gain
ifneq ($(OSTYPE),win)
	cp -p mp3gain$(EXE_EXT) "$(INSTALL_PATH)"
ifeq ($(OSTYPE),beos)
	mimeset -f "$(INSTALL_PATH)/mp3gain$(EXE_EXT)"
endif
else
	@echo install target is not implemented on windows
endif

uninstall:
ifneq ($(OSTYPE),win)
	-rm -f "$(INSTALL_PATH)/mp3gain$(EXE_EXT)"
else
	@echo uninstall target is not implemented on windows
endif

clean: 
	-rm -rf mp3gain$(EXE_EXT) mp3gain.zip $(OBJS) $(RC_OBJ)

dist:   clean
ifneq ($(OSTYPE),win)
ifneq ($(OSTYPE),beos)
	zip -r mp3gain.zip * -x "CVS/*" "*/CVS/*"
endif
else
	@echo dist target is not implemented on windows and beos
endif
