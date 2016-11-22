#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class CoreDLNAServer;
@class CoreDLNAResource;

@interface CoreDLNAFile : NSManagedObject

@property (nonatomic, retain) NSString * id_;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * class_type;
@property (nonatomic, retain) NSDate * date;
@property (nonatomic, retain) CoreDLNAServer *server;
@property (nonatomic, retain) NSSet *resources;

@end

@interface CoreDLNAFile (CoreDataGeneratedAccessors)

- (void)addResourcesObject:(CoreDLNAResource *)value;
- (void)removeResourcesObject:(CoreDLNAResource *)value;
- (void)addResources:(NSSet *)values;
- (void)removeResources:(NSSet *)values;

@end
