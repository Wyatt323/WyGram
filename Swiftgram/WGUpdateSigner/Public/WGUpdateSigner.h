// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
// MARK: WyGram — in-process certificate signing; private material never leaves the device.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface WGUpdateSigner : NSObject
+ (NSArray<NSData *> * _Nullable)installedProfiles:(NSString *)installedApp certificate:(NSData *)p12 password:(NSString *)password error:(NSError **)error;
+ (BOOL)validateProfiles:(NSArray<NSData *> *)profiles error:(NSError **)error;
+ (BOOL)validateInstalledApp:(NSString *)installedApp certificate:(NSData *)p12 password:(NSString *)password profiles:(NSArray<NSData *> *)profiles error:(NSError **)error;
+ (NSString * _Nullable)validateCertificate:(NSData *)p12 password:(NSString *)password installedApp:(NSString *)installedApp error:(NSError **)error;
+ (BOOL)validateTrollStoreIPA:(NSString *)ipa installedApp:(NSString *)installedApp expectedVersion:(NSString *)version expectedBuild:(NSString *)build error:(NSError **)error;
+ (BOOL)prepareIPA:(NSString *)ipa output:(NSString *)output installedApp:(NSString *)installedApp certificate:(NSData *)p12 password:(NSString *)password profiles:(NSArray<NSData *> *)profiles expectedVersion:(NSString *)version expectedBuild:(NSString *)build error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
