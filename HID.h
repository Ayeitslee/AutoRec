// Minimal private IOKit HID declarations (not in the public SDK).
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef void (*IOHIDEventSystemClientEventCallback)(void *target, void *refcon, void *queue, IOHIDEventRef event);

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef a);
void IOHIDEventSystemClientScheduleWithRunLoop(IOHIDEventSystemClientRef c, CFRunLoopRef rl, CFStringRef mode);
void IOHIDEventSystemClientUnscheduleWithRunLoop(IOHIDEventSystemClientRef c, CFRunLoopRef rl, CFStringRef mode);
void IOHIDEventSystemClientRegisterEventCallback(IOHIDEventSystemClientRef c, IOHIDEventSystemClientEventCallback cb, void *target, void *refcon);
void IOHIDEventSystemClientUnregisterEventCallback(IOHIDEventSystemClientRef c);
void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef c, IOHIDEventRef e);

uint32_t IOHIDEventGetType(IOHIDEventRef e);
CFArrayRef IOHIDEventGetChildren(IOHIDEventRef e);
double IOHIDEventGetFloatValue(IOHIDEventRef e, uint32_t field);
CFIndex IOHIDEventGetIntegerValue(IOHIDEventRef e, uint32_t field);
void IOHIDEventSetSenderID(IOHIDEventRef e, uint64_t id);
void IOHIDEventAppendEvent(IOHIDEventRef parent, IOHIDEventRef child, uint32_t options);

IOHIDEventRef IOHIDEventCreateDigitizerEvent(CFAllocatorRef a, uint64_t ts, uint32_t type, uint32_t index, uint32_t identity,
    uint32_t eventMask, uint32_t buttonMask, double x, double y, double z, double tipPressure, double barrelPressure,
    Boolean range, Boolean touch, uint32_t options);
IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(CFAllocatorRef a, uint64_t ts, uint32_t index, uint32_t identity,
    uint32_t eventMask, double x, double y, double z, double tipPressure, double twist, Boolean range, Boolean touch, uint32_t options);
#ifdef __cplusplus
}
#endif

#define kHIDTypeDigitizer 11
#define HIDField(type, n) (((type) << 16) | (n))
#define kFieldDigX        HIDField(kHIDTypeDigitizer, 0)
#define kFieldDigY        HIDField(kHIDTypeDigitizer, 1)
#define kFieldDigIndex    HIDField(kHIDTypeDigitizer, 5)
#define kFieldDigIdentity HIDField(kHIDTypeDigitizer, 6)
#define kFieldDigEventMask HIDField(kHIDTypeDigitizer, 7)
#define kFieldDigRange    HIDField(kHIDTypeDigitizer, 9)
#define kFieldDigTouch    HIDField(kHIDTypeDigitizer, 10)
#define kDigEventRange    0x01
#define kDigEventTouch    0x02
#define kDigTransducerHand 3
