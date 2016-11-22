#import "Obj-DLNAWrapper.h"

#include "obj-dlna.h"

static dispatch_once_t onceToken;
static dispatch_semaphore_t sema;

@implementation ObjDLNAWrapper

+(void)setupSemaphore
{
    dispatch_once(&onceToken, ^{
        sema = dispatch_semaphore_create(1L);
    });
}

+(BOOL)initDLNA
{
    [ObjDLNAWrapper setupSemaphore];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    int rc = objdlna_init();
    dispatch_semaphore_signal(sema);
    return rc == 0;
}

+(NSString *)getMediaServersXML
{
    if(![ObjDLNAWrapper initDLNA])
    {
        return nil;
    }

    char *outXML = NULL;
    [ObjDLNAWrapper setupSemaphore];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    int rc = objdlna_getMediaServersXML(&outXML);
    dispatch_semaphore_signal(sema);

    if(rc == 0)
    {
        NSString *fileXML = [NSString stringWithUTF8String:outXML];
        free(outXML);
        return fileXML;
    }
    else
    {
        return nil;
    }
}

+(NSString *)getFilesXML:(NSString *)devName atID:(NSString *)objectId
{
    if(![ObjDLNAWrapper initDLNA])
    {
        return nil;
    }

    char *outXML = NULL;
    [ObjDLNAWrapper setupSemaphore];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    int rc = objdlna_getFilesAtIdXML(devName.UTF8String, objectId.UTF8String, &outXML);
    dispatch_semaphore_signal(sema);

    if(rc == 0)
    {
        NSString *fileXML = [NSString stringWithUTF8String:outXML];
        free(outXML);
        return fileXML;
    }
    else
    {
        return nil;
    }
}

+(BOOL)cleanupDLNA
{
    [ObjDLNAWrapper setupSemaphore];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    int rc = objdlna_cleanup();
    dispatch_semaphore_signal(sema);
    return rc == 0;
}

@end
