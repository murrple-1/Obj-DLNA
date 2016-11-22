#import "DLNAManager.h"
#import "DLNAManager+Private.h"
#import "CoreDLNAServer.h"
#import "CoreDLNAFile.h"
#import "CoreDLNAResource.h"
#import "DLNAServer.h"
#import "DLNAFile.h"
#import "DLNAResource.h"
#import "Obj-DLNAWrapper.h"

#import <SystemConfiguration/CaptiveNetwork.h>
#import "GDataXMLNode.h"

#define DEFAULT_TIME_BETWEEN_SCAN_UPDATES 10.0
#define DEFAULT_TIME_BETWEEN_NETWORK_UPDATES 5.0
#define DEFAULT_MAX_SEARCH_DEPTH 10

static NSMutableDictionary *_contexts = nil;
static NSMutableDictionary *_queues = nil;

@implementation DLNAManager

-(id)initWithMaxSearchDepth:(unsigned int)maxSearchDepth modelURL:(NSURL *)modelURL
{
    if(self = [super init])
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            _contexts = [[NSMutableDictionary alloc] init];
            _queues = [[NSMutableDictionary alloc] init];
        });

        _context = [_contexts objectForKey:modelURL];
        if(!_context)
        {
            NSManagedObjectModel *managedObjectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
            NSPersistentStoreCoordinator *storeCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:managedObjectModel];
            NSURL *cacheDir = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
            NSURL *storeDir = [cacheDir URLByAppendingPathComponent:@"com.obj-dlna"];
            if(![[NSFileManager defaultManager] fileExistsAtPath:[storeDir path]])
            {
                NSError *error = nil;
                if(![[NSFileManager defaultManager] createDirectoryAtURL:storeDir withIntermediateDirectories:YES attributes:nil error:&error])
                {
                    return nil;
                }
            }
            NSURL *storeURL = [storeDir URLByAppendingPathComponent:@"DLNAModel.sqlite"];
            [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil];
            [storeCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:nil error:nil];

            _context = [[NSManagedObjectContext alloc] init];
            [_context setPersistentStoreCoordinator:storeCoordinator];

            [_contexts setObject:_context forKey:modelURL];
        }

        _queue = [_queues objectForKey:modelURL];
        if(!_queue)
        {
            _queue = dispatch_queue_create("com.obj-dlna", DISPATCH_QUEUE_CONCURRENT);

            [_queues setObject:_queue forKey:modelURL];
        }

        self.timeBetweenScanUpdates = DEFAULT_TIME_BETWEEN_SCAN_UPDATES;
        self.timeBetweenNetworkUpdates = DEFAULT_TIME_BETWEEN_NETWORK_UPDATES;
        self.maxSearchDepth = maxSearchDepth;
    }
    return self;
}

-(id)initWithMaxSearchDepth:(unsigned int)maxSearchDepth
{
    NSString *modelBundlePath = [[NSBundle mainBundle] pathForResource:@"Obj-DLNAModel" ofType:@"bundle"];
    NSBundle *modelBundle = [NSBundle bundleWithPath:modelBundlePath];
    NSURL *modelURL = [modelBundle URLForResource:@"DLNAModel" withExtension:@"momd"];

    return [self initWithMaxSearchDepth:maxSearchDepth modelURL:modelURL];
}

-(id)init
{
    return [self initWithMaxSearchDepth:DEFAULT_MAX_SEARCH_DEPTH];
}

-(void)updateBlock:(BOOL (^)())shouldStop
{
    if(shouldStop())
    {
        return;
    }

    void (^escapeFunc)() = ^() {
        dispatch_barrier_async(_queue, ^{
            if(shouldStop())
            {
                return;
            }

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeBetweenScanUpdates * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0L), ^{
                [self updateBlock:shouldStop];
            });
        });
    };

    dispatch_queue_t dlnaPollQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0L);

    dispatch_async(_queue, ^{
        if(shouldStop())
        {
            return;
        }
        NSError *error = nil;
        NSArray *managedServers = [self getManagedObjectsWithEntityName:@"Server" predicate:nil error:&error];

        dispatch_barrier_async(_queue, ^{
            if(shouldStop())
            {
                return;
            }

            if(!managedServers)
            {
                [self.delegate contextFetchingError:error];
                escapeFunc();
                return;
            }

            for(NSManagedObject *obj in managedServers)
            {
                [_context deleteObject:obj];
            }

            NSError *error = nil;
            BOOL saveSuccess = _context.hasChanges ? [_context save:&error] : YES;
            if(!saveSuccess)
            {
                [_context rollback];
                [self.delegate contextFetchingError:error];
                escapeFunc();
                return;
            }
        });

        dispatch_async(dlnaPollQueue, ^{
            if(shouldStop())
            {
                return;
            }

            NSError *error = nil;
            NSArray *newServers = [self loadServersWithError:&error shouldStop:shouldStop];

            dispatch_barrier_async(_queue, ^{
                if(shouldStop())
                {
                    return;
                }

                if(!newServers)
                {
                    [self.delegate contextFetchingError:error];
                    escapeFunc();
                    return;
                }

                for(DLNAServer *newServer in newServers)
                {
                    CoreDLNAServer *newCoreServer = [NSEntityDescription insertNewObjectForEntityForName:@"Server" inManagedObjectContext:_context];
                    newCoreServer.name = newServer.name;
                }

                NSError *error = nil;
                BOOL saveSuccess = _context.hasChanges ? [_context save:&error] : YES;
                if(!saveSuccess)
                {
                    [_context rollback];
                    [self.delegate contextFetchingError:error];
                    escapeFunc();
                    return;
                }
            });

            __block NSUInteger counter = 0;
            NSUInteger totalServers = newServers.count;

            for(DLNAServer *newServer in newServers)
            {
                dispatch_async(dlnaPollQueue, ^{
                    if(shouldStop())
                    {
                        return;
                    }

                    NSError *error = nil;
                    NSArray *newFiles = [self loadFilesFromServers:@[newServer] error:&error shouldStop:shouldStop];

                    if(shouldStop())
                    {
                        return;
                    }

                    dispatch_barrier_async(_queue, ^{
                        if(shouldStop())
                        {
                            return;
                        }

                        if(!newFiles)
                        {
                            [self.delegate contextFetchingError:error];
                            if(++counter == totalServers)
                            {
                                escapeFunc();
                            }
                            return;
                        }

                        NSError *error = nil;
                        NSArray *coreServers = [self getManagedObjectsWithEntityName:@"Server" predicate:[NSPredicate predicateWithFormat:@"SELF.name LIKE %@", newServer.name] error:&error];
                        CoreDLNAServer *coreServer = coreServers.count ? [coreServers firstObject] : nil;

                        if(coreServer)
                        {
                            for(DLNAFile *newFile in newFiles)
                            {
                                CoreDLNAFile *newCoreFile = [NSEntityDescription insertNewObjectForEntityForName:@"File" inManagedObjectContext:_context];
                                newCoreFile.id_ = newFile.id_;
                                newCoreFile.title = newFile.title;
                                newCoreFile.class_type = newFile.class_type;
                                newCoreFile.date = newFile.date;
                                [coreServer addFilesObject:newCoreFile];

                                for(NSUInteger i = 0; i < newFile.resources.count; i++)
                                {
                                    DLNAResource *newResource = [newFile.resources objectAtIndex:i];
                                    CoreDLNAResource *newCoreResource = [NSEntityDescription insertNewObjectForEntityForName:@"Resource" inManagedObjectContext:_context];
                                    newCoreResource.orderNum = @(i);
                                    newCoreResource.protocolInfo = newResource.protocolInfo;
                                    newCoreResource.resolution = newResource.resolution;
                                    newCoreResource.size = newResource.size;
                                    newCoreResource.uri = newResource.uri;
                                    [newCoreFile addResourcesObject:newCoreResource];
                                }
                            }
                        }

                        BOOL saveSuccess = _context.hasChanges ? [_context save:&error] : YES;
                        if(!saveSuccess)
                        {
                            [_context rollback];
                            [self.delegate contextFetchingError:error];
                            if(++counter == totalServers)
                            {
                                escapeFunc();
                            }
                            return;
                        }

                        if(++counter == totalServers)
                        {
                            escapeFunc();
                        }
                    });
                });
            }
        });
    });
}

-(void)networkWatchBlock:(BOOL (^)())shouldStop
{
    if(shouldStop())
    {
        return;
    }

    NSArray *ifs = (__bridge_transfer NSArray *)(CNCopySupportedInterfaces());
    NSString *ifnam = ifs.count ? [ifs objectAtIndex:0] : nil;

    if(ifnam)
    {
        NSDictionary *info = (__bridge_transfer NSDictionary *)(CNCopyCurrentNetworkInfo((__bridge CFStringRef)ifnam));
        NSString *currentSSID = [info objectForKey:(__bridge NSString *)(kCNNetworkInfoKeySSID)];

        if(![currentSSID isEqualToString:_currentSSID])
        {
            _currentSSID = currentSSID;

            void (^escapeFunc)() = ^() {
                dispatch_barrier_async(_queue, ^{
                    if(shouldStop())
                    {
                        return;
                    }

                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.timeBetweenNetworkUpdates * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0L), ^{
                        [self networkWatchBlock:shouldStop];
                    });
                });
            };

            dispatch_async(_queue, ^{
                if(shouldStop())
                {
                    return;
                }

                NSError *error = nil;
                NSArray *managedServers = [self getManagedObjectsWithEntityName:@"Server" predicate:nil error:&error];

                dispatch_barrier_async(_queue, ^{
                    if(shouldStop())
                    {
                        return;
                    }

                    if(!managedServers)
                    {
                        [self.delegate contextFetchingError:error];
                        escapeFunc();
                        return;
                    }

                    for(NSManagedObject *obj in managedServers)
                    {
                        [_context deleteObject:obj];
                    }

                    NSError *error = nil;
                    BOOL saveSuccess = _context.hasChanges ? [_context save:&error] : YES;
                    if(!saveSuccess)
                    {
                        [_context rollback];
                        [self.delegate contextFetchingError:error];
                        escapeFunc();
                        return;
                    }
                });

                escapeFunc();
            });
        }
    }
}

-(void)startUpdating
{
    dispatch_barrier_async(_queue, ^{
        if(_started)
        {
            return;
        }
        _started = YES;

        [ObjDLNAWrapper initDLNA];

        BOOL (^shouldStop)() = ^BOOL() {
            return !self->_started;
        };

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0L), ^{
            [self networkWatchBlock:shouldStop];
        });

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0L), ^{
            [self updateBlock:shouldStop];
        });
    });
}

-(void)stopUpdating
{
    dispatch_barrier_async(_queue, ^{
        if(!_started)
        {
            return;
        }
        _started = NO;

        [ObjDLNAWrapper cleanupDLNA];
    });
}

-(NSArray *)loadServersWithError:(NSError *__autoreleasing *)error shouldStop:(BOOL (^)())shouldStop
{
    NSString *serversStr = [ObjDLNAWrapper getMediaServersXML];
    if(shouldStop())
    {
        return nil;
    }
    GDataXMLDocument *serverDoc = [[GDataXMLDocument alloc] initWithXMLString:serversStr options:0 error:error];
    if(!serverDoc)
    {
        return nil;
    }

    GDataXMLElement *serversEle = serverDoc.rootElement;

    NSMutableArray *servers = [NSMutableArray array];
    for(GDataXMLElement *serverEle in [serversEle elementsForName:@"server"])
    {
        DLNAServer *server = [[DLNAServer alloc] init];
        server.name = [[serverEle attributeForName:@"name"] stringValue];
        [servers addObject:server];
    }

    return servers;
}

-(NSArray *)loadFilesFromServers:(NSArray *)servers error:(NSError *__autoreleasing *)error shouldStop:(BOOL(^)())shouldStop
{
    NSMutableSet *filterURIs = [NSMutableSet set];
    NSMutableArray *files = [[NSMutableArray alloc] init];
    for(DLNAServer *server in servers)
    {
        NSArray *serverFiles = [self traverseContainerId:@"0" withServer:server filterURIs:filterURIs error:error currentDepth:0 shouldStop:shouldStop];
        if(!serverFiles)
        {
            return nil;
        }
        [files addObjectsFromArray:serverFiles];

        if(shouldStop())
        {
            return nil;
        }
    }
    return files;
}

-(NSArray *)traverseContainerId:(NSString *)containerId withServer:(DLNAServer *)server filterURIs:(NSMutableSet *)filterURIs error:(NSError *__autoreleasing *)error currentDepth:(unsigned int)currentDepth shouldStop:(BOOL (^)())shouldStop
{
    if(currentDepth >= self.maxSearchDepth)
    {
        return @[];
    }
    NSString *filesXML = [ObjDLNAWrapper getFilesXML:server.name atID:containerId];
    if(!filesXML)
    {
        return nil;
    }

    if(shouldStop())
    {
        return nil;
    }

    GDataXMLDocument *filesDoc = [[GDataXMLDocument alloc] initWithXMLString:filesXML options:0 error:error];
    if(!filesDoc)
    {
        return nil;
    }
    NSMutableArray *retVal = [[NSMutableArray alloc] init];

    GDataXMLElement *rootElement = filesDoc.rootElement;
    NSArray *files = [self addFilesFromXML:rootElement inServer:server filterURIs:filterURIs error:error];
    if(!files)
    {
        return nil;
    }
    [retVal addObjectsFromArray:files];

    if(shouldStop())
    {
        return nil;
    }

    NSSet *containerIds = [self getContainerIdsFromXML:rootElement];
    unsigned int newDepth = currentDepth + 1;
    for(NSString *containerId in containerIds)
    {
        NSArray *serverFiles = [self traverseContainerId:containerId withServer:server filterURIs:filterURIs error:error currentDepth:newDepth shouldStop:shouldStop];
        if(!serverFiles)
        {
            return nil;
        }
        [retVal addObjectsFromArray:serverFiles];
        if(shouldStop())
        {
            return nil;
        }
    }

    return retVal;
}

-(NSSet *)getContainerIdsFromXML:(GDataXMLElement *)rootElement
{
    NSMutableSet *retVal = [NSMutableSet set];
    for(GDataXMLElement *containerEle in [rootElement elementsForName:@"container"])
    {
        NSString *id_ = [[containerEle attributeForName:@"id"] stringValue];
        [retVal addObject:id_];
    }
    return retVal;
}

-(NSArray *)addFilesFromXML:(GDataXMLElement *)rootElement inServer:(DLNAServer *)server filterURIs:(NSMutableSet *)filterURIs error:(NSError *__autoreleasing *)error
{
    NSMutableArray *files = [[NSMutableArray alloc] init];
    for(GDataXMLElement *fileEle in [rootElement elementsForName:@"file"])
    {
        NSArray *resEles = [fileEle elementsForName:@"res"];
        if(resEles.count > 0)
        {
            GDataXMLElement *mainResEle = [resEles objectAtIndex:0];
            NSString *mainUri = [mainResEle stringValue];
            NSString *oldUri = [filterURIs member:mainUri];
            if(!oldUri)
            {
                [filterURIs addObject:mainUri];

                DLNAFile *file = [[DLNAFile alloc] init];
                file.id_ = [[fileEle attributeForName:@"id"] stringValue];
                file.title = [[fileEle attributeForName:@"title"] stringValue];
                file.class_type = [[fileEle attributeForName:@"class"] stringValue];

                NSString *dateStr = [[fileEle attributeForName:@"date"] stringValue];
                NSDate *date = [DLNAManager dateFromString:dateStr];
                file.date = date;

                [self addResFromXML:fileEle inFile:file error:error];

                [files addObject:file];
            }
        }
    }

    return files;
}

-(void)addResFromXML:(GDataXMLElement *)rootElement inFile:(DLNAFile *)file error:(NSError *__autoreleasing *)error
{
    NSArray *resEles = [rootElement elementsForName:@"res"];
    NSMutableArray *resources = [[NSMutableArray alloc] init];
    for(int i = 0; i < resEles.count; i++)
    {
        GDataXMLElement *resEle = [resEles objectAtIndex:i];
        DLNAResource *resource = [[DLNAResource alloc] init];
        resource.protocolInfo = [[resEle attributeForName:@"protocolInfo"] stringValue];
        resource.resolution = [[resEle attributeForName:@"resolution"] stringValue];
        resource.uri = [resEle stringValue];
        NSString *sizeStr = [[resEle attributeForName:@"size"] stringValue];
        if(sizeStr)
        {
            resource.size = [NSNumber numberWithLongLong:[sizeStr longLongValue]];
        }

        [resources addObject:resource];
    }
    file.resources = resources;
}

+(NSDate *)dateFromString:(NSString *)dateStr
{
    if(!dateStr)
    {
        return nil;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSDate *date = nil;
    if(!date)
    {
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZ"];
        date = [dateFormatter dateFromString:dateStr];
    }

    if(!date)
    {
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
        date = [dateFormatter dateFromString:dateStr];
    }

    if(!date)
    {
        [dateFormatter setDateFormat:@"yyyy-MM-dd"];
        date = [dateFormatter dateFromString:dateStr];
    }

    return date;
}

-(NSArray *)getFilesFromServer:(NSString *)deviceName error:(NSError *__autoreleasing *)error
{
    __block NSArray *files = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0L);
    dispatch_async(_queue, ^{
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"server.name == %@", deviceName];
        files = [self getFilesWithPredicate:predicate error:error];
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return files;
}

-(NSArray *)getAllFilesWithError:(NSError *__autoreleasing *)error
{
    __block NSArray *files = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0L);
    dispatch_async(_queue, ^{
        files = [self getFilesWithPredicate:nil error:error];
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return files;
}

-(NSArray *)getAllServersWithError:(NSError *__autoreleasing *)error
{
    __block NSArray *servers = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0L);
    dispatch_async(_queue, ^{
        servers = [self getServersWithPredicate:nil error:error];
        dispatch_semaphore_signal(sema);
    });
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return servers;
}

-(NSArray *)getServersWithPredicate:(NSPredicate *)predicate error:(NSError *__autoreleasing *)error
{
    NSArray *fetchedObjects = [self getManagedObjectsWithEntityName:@"Server" predicate:predicate error:error];
    NSMutableArray *retVal = [NSMutableArray array];
    for(CoreDLNAServer *server in fetchedObjects)
    {
        DLNAServer *s = [[DLNAServer alloc] init];
        s.name = server.name;
        [retVal addObject:s];
    }
    return retVal;
}

-(NSArray *)getFilesWithPredicate:(NSPredicate *)predicate error:(NSError *__autoreleasing *)error
{
    NSArray *fetchedObjects = [self getManagedObjectsWithEntityName:@"File" predicate:predicate error:error];
    NSMutableArray *retVal = [NSMutableArray array];
    for(CoreDLNAFile *file in fetchedObjects)
    {
        DLNAFile *f = [[DLNAFile alloc] init];
        f.id_ = file.id_;
        f.title = file.title;
        f.class_type = file.class_type;
        f.date = file.date;
        f.serverName = file.server.name;

        NSArray *resources = [[file.resources allObjects] sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            CoreDLNAResource *r1 = (CoreDLNAResource *)obj1;
            CoreDLNAResource *r2 = (CoreDLNAResource *)obj2;

            return [r1.orderNum compare:r2.orderNum];
        }];

        NSMutableArray *fResources = [NSMutableArray array];
        for(CoreDLNAResource *resource in resources)
        {
            DLNAResource *r = [[DLNAResource alloc] init];
            r.protocolInfo = resource.protocolInfo;
            r.resolution = resource.resolution;
            r.size = resource.size;
            r.uri = resource.uri;
            r.fileId = f.id_;
            [fResources addObject:r];
        }
        f.resources = fResources;
        [retVal addObject:f];
    }
    return retVal;
}

-(NSArray *)getManagedObjectsWithEntityName:(NSString *)entityName predicate:(NSPredicate *)predicate error:(NSError *__autoreleasing *)error
{
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    NSEntityDescription *entity = [NSEntityDescription entityForName:entityName inManagedObjectContext:_context];
    [fetchRequest setEntity:entity];
    [fetchRequest setPredicate:predicate];

    NSArray *fetchedObjects = [_context executeFetchRequest:fetchRequest error:error];
    return fetchedObjects;
}

@end
