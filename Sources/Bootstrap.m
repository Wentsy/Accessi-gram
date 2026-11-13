#import <Foundation/Foundation.h>
extern void AGStart(void);
__attribute__((constructor)) static void start(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ AGStart(); });
}
