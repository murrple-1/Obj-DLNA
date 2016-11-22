#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@protocol DLNAManagerDelegate <NSObject>

@required
-(void)contextFetchingError:(NSError *)error;
-(void)contextSavingError:(NSError *)error;

@end

@interface DLNAManager : NSObject
{
    @private
    NSManagedObjectContext *_context;
    dispatch_queue_t _queue;
    NSString *_currentSSID;
    BOOL _started;
}

@property (assign) NSTimeInterval timeBetweenScanUpdates;
@property (assign) NSTimeInterval timeBetweenNetworkUpdates;
@property (nonatomic, weak) id<DLNAManagerDelegate> delegate;
@property (assign) unsigned int maxSearchDepth;

-(id)initWithMaxSearchDepth:(unsigned int)maxSearchDepth;

-(void)startUpdating;
-(void)stopUpdating;

-(NSArray *)getFilesFromServer:(NSString *)deviceName error:(NSError *__autoreleasing *)error;
-(NSArray *)getAllFilesWithError:(NSError *__autoreleasing *)error;
-(NSArray *)getAllServersWithError:(NSError *__autoreleasing *)error;

@end
