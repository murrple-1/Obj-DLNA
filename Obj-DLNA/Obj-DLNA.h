/* -*- Mode: C; tab-width: 8; indent-tabs-mode: t; c-basic-offset: 8 -*- */

#ifndef OBJ_DLNA_H
#define OBJ_DLNA_H

#include "ixml.h"

int objdlna_init();

int objdlna_getMediaServersXML(char **outXML);

int objdlna_getFilesAtIdXML(const char *const devName, const char *const objectId, char **outXML);

int objdlna_cleanup();

#endif

