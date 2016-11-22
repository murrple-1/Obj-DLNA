#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class CoreDLNAFile;

@interface CoreDLNAServer : NSManagedObject

@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSSet *files;
@end

@interface CoreDLNAServer (CoreDataGeneratedAccessors)

- (void)addFilesObject:(CoreDLNAFile *)value;
- (void)removeFilesObject:(CoreDLNAFile *)value;
- (void)addFiles:(NSSet *)values;
- (void)removeFiles:(NSSet *)values;

@end
