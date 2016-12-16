/* -*- Mode: C; tab-width: 8; indent-tabs-mode: t; c-basic-offset: 2 -*- */

#include "didl_object.h"
#include "talloc_util.h"
#include "content_dir.h"
#include "device_list.h"
#include "xml_util.h"
#include "device.h"
#include "upnp/ixml.h"

static TALLOC_CTX *talloc_ctx = NULL;
static bool enabled = false;

static bool shouldIgnoreDIDLObject(const DIDLObject *const o, const char *const devName)
{
    if(strstr(devName, "Flex Media Server"))
    {
        if(o->is_container && strstr(o->id, "_") != NULL)
        {
            return true;
        }
    }
    return false;
}

static IXML_ERRORCODE setResAttribute(IXML_Element *resEle, IXML_Element *dupEle, const char *attrName)
{
    const char *attrValue = ixmlElement_getAttribute(resEle, attrName);
    if(attrValue != NULL)
    {
        return ixmlElement_setAttribute(dupEle, attrName, attrValue);
    }
    else
    {
        return IXML_SUCCESS;
    }
}

/*
 * Grabbing only the res attributes defined in http://www.upnp.org/schemas/av/didl-lite-v2.xsd
 */
static IXML_ERRORCODE duplicateResElement(IXML_Document *xmlDoc, IXML_Element *resEle, IXML_Element **dupEle)
{
    IXML_Element *ele = ixmlDocument_createElement(xmlDoc, "res");
    if(ele == NULL)
    {
        return IXML_FAILED;
    }

    IXML_ERRORCODE rc;

    const char *resValue = XMLUtil_GetElementValue(resEle);
    if(resValue == NULL)
    {
        goto fail;
    }
    IXML_Node *resValueNode = ixmlDocument_createTextNode(xmlDoc, resValue);
    if(resValueNode == NULL)
    {
        goto fail;
    }

    if((rc = ixmlNode_appendChild(&ele->n, resValueNode)) != IXML_SUCCESS)
    {
        ixmlNode_free(resValueNode);
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "importUri")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "protocolInfo")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "size")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "duration")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "bitrate")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "sampleFrequency")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "bitsPerSample")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "nrAudioChannels")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "resolution")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "colorDepth")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "tspec")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "allowedUse")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "validityStart")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "validityEnd")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "remainingTime")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "updateCount")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "usageInfo")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "rightsInfoURI")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "contentInfoURI")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "recordQuality")) != IXML_SUCCESS)
    {
        goto fail;
    }

    if((rc = setResAttribute(resEle, ele, "protection")) != IXML_SUCCESS)
    {
        goto fail;
    }

    goto success;

fail:
    ixmlElement_free(ele);
    return rc;
success:
    *dupEle = ele;
    return IXML_SUCCESS;
}

static int browseAtId(const char *const devName, const char *const objectId, IXML_Document **outXML)
{
    IXML_Document *xmlDoc = ixmlDocument_createDocument();
    if(xmlDoc == NULL)
    {
        ixmlDocument_free(xmlDoc);
        return -1;
    }

    IXML_Element *filesElement = ixmlDocument_createElement(xmlDoc, "files");
    if(filesElement == NULL)
    {
        ixmlDocument_free(xmlDoc);
        return -1;
    }

    int rc = ixmlNode_appendChild(&xmlDoc->n, &filesElement->n);
    if(rc != IXML_SUCCESS)
    {
        ixmlDocument_free(xmlDoc);
        return -1;
    }

    const ContentDir_BrowseResult *current = NULL;
    DEVICE_LIST_CALL_SERVICE(current, devName, CONTENT_DIR_SERVICE_TYPE, ContentDir, Browse,
                             talloc_ctx, objectId, CONTENT_DIR_BROWSE_DIRECT_CHILDREN);
    if (current && current->children)
    {
        const DIDLObject *o = NULL;
        PTR_ARRAY_FOR_EACH_PTR(current->children->objects, o)
        {
            if(shouldIgnoreDIDLObject(o, devName))
            {
                continue;
            }
            if (o->is_container)
            {
                IXML_Element *containerEle = ixmlDocument_createElement(xmlDoc, "container");
                if(containerEle == NULL)
                {
                    ixmlDocument_free(xmlDoc);
                    talloc_free((void *)current);
                    return -1;
                }

                int rc = ixmlNode_appendChild(&filesElement->n, &containerEle->n);
                if(rc != IXML_SUCCESS)
                {
                    ixmlDocument_free(xmlDoc);
                    talloc_free((void *)current);
                    return -1;
                }

                ixmlElement_setAttribute(containerEle, "id", o->id);
                ixmlElement_setAttribute(containerEle, "title", o->title);
                ixmlElement_setAttribute(containerEle, "class", o->cds_class);
            }
            else
            {
                IXML_Element *fileElement = ixmlDocument_createElement(xmlDoc, "file");
                if(fileElement == NULL)
                {
                    ixmlDocument_free(xmlDoc);
                    talloc_free((void *)current);
                    return -1;
                }

                int rc = ixmlNode_appendChild(&filesElement->n, &fileElement->n);
                if(rc != IXML_SUCCESS)
                {
                    ixmlDocument_free(xmlDoc);
                    talloc_free((void *)current);
                    return -1;
                }

                ixmlElement_setAttribute(fileElement, "id", o->id);
                ixmlElement_setAttribute(fileElement, "title", o->title);
                ixmlElement_setAttribute(fileElement, "class", o->cds_class);

                const char *dateValue = XMLUtil_FindFirstElementValue(&o->element->n, "dc:date", false, false);
                if(dateValue != NULL)
                {
                    ixmlElement_setAttribute(fileElement, "date", dateValue);
                }

                IXML_NodeList *resNodes = ixmlElement_getElementsByTagName(o->element, "res");
                if(resNodes != NULL)
                {
                    for(unsigned long i = 0L; i < ixmlNodeList_length(resNodes); i++)
                    {
                        IXML_Element *resEle = (IXML_Element *)ixmlNodeList_item(resNodes, i);
                        IXML_Element *dupResEle = NULL;
                        if(duplicateResElement(xmlDoc, resEle, &dupResEle) != IXML_SUCCESS)
                        {
                            ixmlDocument_free(xmlDoc);
                            talloc_free((void *)current);
                            return -1;
                        }
                        ixmlNode_appendChild(&fileElement->n, &dupResEle->n);
                    }
                    ixmlNodeList_free(resNodes);
                }
            }
        }
        PTR_ARRAY_FOR_EACH_PTR_END;

        talloc_free((void *)current);
    }
    *outXML = xmlDoc;
    return 0;
}

static int browseDevices(IXML_Document **outXML)
{
    IXML_Document *xmlDoc = ixmlDocument_createDocument();
    if (xmlDoc == NULL)
    {
        return -1;
    }

    IXML_Element *serversEle = NULL;
    ixmlDocument_createElementEx(xmlDoc, "servers", &serversEle);
    if (serversEle == NULL)
    {
        return -1;
    }

    int ret = ixmlNode_appendChild(&xmlDoc->n, &serversEle->n);
    if (ret != IXML_SUCCESS)
    {
        return -1;
    }

    PtrArray *names = DeviceList_GetDevicesNames(talloc_ctx);

    const char *devName;
    PTR_ARRAY_FOR_EACH_PTR(names, devName)
    {
        IXML_Element *serverEle = NULL;
        ixmlDocument_createElementEx(xmlDoc, "server", &serverEle);
        if (serverEle == NULL)
        {
            return -1;
        }

        int ret = ixmlNode_appendChild(&serversEle->n, &serverEle->n);
        if (ret != IXML_SUCCESS)
        {
            return -1;
        }

        ixmlElement_setAttribute(serverEle, "name", devName);
    }
    PTR_ARRAY_FOR_EACH_PTR_END;
    talloc_free(names);

    *outXML = xmlDoc;

    return 0;
}

int objdlna_init()
{
    if (talloc_ctx == NULL)
    {
        talloc_ctx = talloc_autofree_context();
    }

    if(!enabled)
    {
        int rc = DeviceList_Start(CONTENT_DIR_SERVICE_TYPE, NULL);
        if(rc == 0)
        {
            enabled = true;
        }
        return rc;
    }
    else
    {
        return 0;
    }
}

int objdlna_getMediaServersXML(char **outXML)
{
    int rc = objdlna_init();
    if (rc != 0)
    {
        return -1;
    }

    IXML_Document *xmlDoc = NULL;
    browseDevices(&xmlDoc);
    if (xmlDoc == NULL)
    {
        return -1;
    }
    DOMString xmlStr = ixmlPrintDocument(xmlDoc);
    ixmlDocument_free(xmlDoc);
    if (xmlStr != NULL)
    {
        *outXML = malloc(strlen(xmlStr) + 1);
        if (*outXML)
        {
            strcpy(*outXML, xmlStr);
        }
        ixmlFreeDOMString(xmlStr);
        return 0;
    }
    else
    {
        return -1;
    }
}

int objdlna_getFilesAtIdXML(const char *const devName, const char *const objectId, char **outXML)
{
    int rc = objdlna_init();
    if (rc != 0)
    {
        return -1;
    }

    IXML_Document *outXMLDoc = NULL;
    browseAtId(devName, objectId, &outXMLDoc);

    DOMString xml = ixmlPrintDocument(outXMLDoc);
    ixmlDocument_free(outXMLDoc);
    if (xml)
    {
        *outXML = strdup(xml);
        ixmlFreeDOMString(xml);
        return 0;
    }
    else
    {
        return -1;
    }
}

int objdlna_cleanup()
{
    if(enabled)
    {
        int rc = DeviceList_Stop();
        if(rc == 0)
        {
            enabled = false;
        }
        return rc;
    }
    else
    {
        return 0;
    }
}
