#import <Foundation/Foundation.h>

@interface ObjDLNAWrapper : NSObject

+(BOOL)initDLNA;

+(NSString *)getMediaServersXML;

+(NSString *)getFilesXML:(NSString *)devName atID:(NSString *)objectId;

+(BOOL)cleanupDLNA;

@end
