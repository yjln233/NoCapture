#import "NCUtils.h"
#import "NCPrefs.h"
#import <os/lock.h>

id NCInvoke0(id target, NSString *selectorName) {
    if (!target || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature) return nil;

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    [invocation invoke];

    if (strcmp(signature.methodReturnType, "@") != 0) return nil;
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

id NCInvoke1(id target, NSString *selectorName, id argument) {
    if (!target || selectorName.length == 0) return nil;
    SEL selector = NSSelectorFromString(selectorName);
    if (![target respondsToSelector:selector]) return nil;

    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments < 3) return nil;

    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = target;
    invocation.selector = selector;
    id arg = argument;
    [invocation setArgument:&arg atIndex:2];
    [invocation invoke];

    if (strcmp(signature.methodReturnType, "@") != 0) return nil;
    __unsafe_unretained id result = nil;
    [invocation getReturnValue:&result];
    return result;
}

void NCLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // NSLog 是同步 I/O。本 tweak 的日志点不少落在通知分发、事件回调这类热路径上,
    // 同一条消息重复输出会明显拖慢目标进程,因此每条只打印一次(上限 500 条防内存膨胀)。
    static NSMutableSet<NSString *> *seen = nil;
    static os_unfair_lock logLock = OS_UNFAIR_LOCK_INIT;

    BOOL shouldLog = NO;
    os_unfair_lock_lock(&logLock);
    if (!seen) seen = [NSMutableSet set];
    if (seen.count < 500 && ![seen containsObject:message]) {
        [seen addObject:message];
        shouldLog = YES;
    }
    os_unfair_lock_unlock(&logLock);

    if (shouldLog) {
        NSLog(@"[NoCapture] %@", message);
    }
}
