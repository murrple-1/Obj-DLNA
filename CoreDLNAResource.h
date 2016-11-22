#import <CoreData/CoreData.h>

@class CoreDLNAFile;

@interface CoreDLNAResource : NSManagedObject

@property (nonatomic, retain) NSNumber * orderNum;
@property (nonatomic, retain) NSString * protocolInfo;
@property (nonatomic, retain) NSString * resolution;
@property (nonatomic, retain) NSNumber * size;
@property (nonatomic, retain) NSString * uri;
@property (nonatomic, retain) CoreDLNAFile * file;

@end
