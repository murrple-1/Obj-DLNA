#import <Foundation/Foundation.h>

@interface DLNAFile : NSObject

@property (nonatomic, retain) NSString * id_;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * class_type;
@property (nonatomic, retain) NSDate * date;
@property (nonatomic, retain) NSString * serverName;
@property (nonatomic, retain) NSArray * resources;

@end
