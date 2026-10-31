// Adapted from RegramDev/Regram-ios, acb65027922c1f76818309b21ae1996754a29a94.
// MARK: WyGram
#import "WGUpdateSigner.h"
#import <ZipArchive/ZipArchive.h>
#include "bundle.h"
#include <WGUpdateOpenSSL/openssl/cms.h>
#include <WGUpdateOpenSSL/openssl/pkcs12.h>
#include <WGUpdateOpenSSL/openssl/x509.h>
#include <WGUpdateOpenSSL/openssl/err.h>
#include <list>
#include <mutex>

static std::mutex signerMutex;
static BOOL WGFail(NSError **error, NSInteger code) {
    if (error) *error = [NSError errorWithDomain:@"WGUpdateSigner" code:code userInfo:nil];
    return NO;
}

static BOOL WGProfileFail(NSError **error, NSString *reason, NSString *bundle, NSString *entitlement = @"") {
    if (error) *error = [NSError errorWithDomain:@"WGUpdateSigner" code:3 userInfo:@{
        @"profileReason": reason, @"bundleName": bundle, @"entitlement": entitlement
    }];
    return NO;
}

static uint32_t WGWord(NSData *data, NSUInteger offset, BOOL bigEndian) {
    if (offset > data.length || data.length - offset < 4) return 0;
    const uint8_t *p = (const uint8_t *)data.bytes + offset;
    if (bigEndian) return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
    return ((uint32_t)p[3] << 24) | ((uint32_t)p[2] << 16) | ((uint32_t)p[1] << 8) | p[0];
}

// Only arm64 thin executables are accepted by this updater's release channel.
static NSData *WGSignatureSlot(NSString *executable, uint32_t slot) {
    NSData *data = [NSData dataWithContentsOfFile:executable options:NSDataReadingMappedIfSafe error:nil];
    if (!data || data.length < 32 || WGWord(data, 0, NO) != 0xfeedfacf || WGWord(data, 4, NO) != 0x0100000c) return nil;
    NSUInteger command = 32;
    uint32_t count = WGWord(data, 16, NO);
    if (count > 4096) return nil;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t kind = WGWord(data, command, NO), length = WGWord(data, command + 4, NO);
        if (length < 8 || command > data.length || length > data.length - command) return nil;
        if (kind == 0x1d && length >= 16) {
            NSUInteger base = WGWord(data, command + 8, NO), size = WGWord(data, command + 12, NO);
            if (size < 12 || base > data.length || size > data.length - base || WGWord(data, base, YES) != 0xfade0cc0) return nil;
            uint32_t slots = WGWord(data, base + 8, YES);
            if (slots > (size - 12) / 8) return nil;
            for (uint32_t j = 0; j < slots; j++) {
                if (WGWord(data, base + 12 + j * 8, YES) != slot) continue;
                NSUInteger offset = WGWord(data, base + 16 + j * 8, YES);
                if (offset > size || size - offset < 8) return nil;
                NSUInteger blobSize = WGWord(data, base + offset + 4, YES);
                if (blobSize < 8 || blobSize > size - offset) return nil;
                return [data subdataWithRange:NSMakeRange(base + offset + 8, blobSize - 8)];
            }
        }
        command += length;
    }
    return nil;
}

static NSData *WGDER(X509 *cert) {
    unsigned char *bytes = nullptr;
    int size = i2d_X509(cert, &bytes);
    NSData *result = size > 0 ? [NSData dataWithBytes:bytes length:size] : nil;
    OPENSSL_free(bytes);
    return result;
}

static NSData *WGInstalledCertificate(NSString *executable) {
    NSData *data = WGSignatureSlot(executable, 0x10000);
    if (!data) return nil;
    const unsigned char *p = (const unsigned char *)data.bytes;
    CMS_ContentInfo *cms = d2i_CMS_ContentInfo(nullptr, &p, (long)data.length);
    if (!cms) return nil;
    STACK_OF(X509) *certs = CMS_get1_certs(cms);
    STACK_OF(CMS_SignerInfo) *infos = CMS_get0_SignerInfos(cms);
    NSData *result = nil;
    if (infos && sk_CMS_SignerInfo_num(infos) == 1 && certs) {
        CMS_SignerInfo *info = sk_CMS_SignerInfo_value(infos, 0);
        for (int i = 0; i < sk_X509_num(certs); i++) {
            X509 *cert = sk_X509_value(certs, i);
            if (CMS_SignerInfo_cert_cmp(info, cert) == 0) { result = WGDER(cert); break; }
        }
    }
    sk_X509_pop_free(certs, X509_free);
    CMS_ContentInfo_free(cms);
    return result;
}

static NSData *WGCertificate(NSData *data, NSString *password) {
    const unsigned char *p = (const unsigned char *)data.bytes;
    PKCS12 *p12 = d2i_PKCS12(nullptr, &p, (long)data.length);
    if (!p12) return nil;
    EVP_PKEY *key = nullptr; X509 *cert = nullptr; STACK_OF(X509) *chain = nullptr;
    BOOL valid = PKCS12_parse(p12, password.UTF8String, &key, &cert, &chain) == 1;
    valid = valid && key && cert && X509_check_private_key(cert, key) == 1 && X509_cmp_current_time(X509_get0_notBefore(cert)) < 0 && X509_cmp_current_time(X509_get0_notAfter(cert)) > 0;
    NSData *result = valid ? WGDER(cert) : nil;
    EVP_PKEY_free(key); X509_free(cert); sk_X509_pop_free(chain, X509_free); PKCS12_free(p12);
    ERR_clear_error();
    return result;
}

static NSDictionary *WGProfile(NSData *data) {
    string content;
    if (!ZSignAsset::GetCMSContent(string((const char *)data.bytes, data.length), content)) return nil;
    NSData *plist = [NSData dataWithBytes:content.data() length:content.size()];
    id value = [NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:nil error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static BOOL WGAllowed(id value, id allowed) {
    // A profile can allow a set of scalar values (for example, iCloud's
    // Development/Production environments), or a wildcard for an array.
    if ([value isKindOfClass:NSArray.class]) {
        for (id item in value) {
            if (!WGAllowed(item, allowed)) return NO;
        }
        return YES;
    }
    if ([allowed isKindOfClass:NSArray.class]) {
        for (id candidate in allowed) {
            if (WGAllowed(value, candidate)) return YES;
        }
        return NO;
    }
    if ([value isKindOfClass:NSString.class] && [allowed isKindOfClass:NSString.class]) {
        if ([value isEqual:allowed]) return YES;
        if ([allowed isEqual:@"*"]) return YES;
        return [allowed hasSuffix:@"*"] && [value hasPrefix:[allowed substringToIndex:[allowed length] - 1]];
    }
    if ([value isKindOfClass:NSDictionary.class] && [allowed isKindOfClass:NSDictionary.class]) {
        for (id key in value) {
            // A disabled entitlement requires no additional capability.
            if (CFGetTypeID((__bridge CFTypeRef)value[key]) == CFBooleanGetTypeID() && ![value[key] boolValue]) continue;
            if (!WGAllowed(value[key], allowed[key])) return NO;
        }
        return YES;
    }
    return value && allowed && [value isEqual:allowed];
}

static NSArray<NSString *> *WGBundles(NSString *app) {
    NSMutableArray *result = [NSMutableArray arrayWithObject:app];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:app];
    for (NSString *relative in enumerator) {
        if ([relative.pathExtension isEqual:@"appex"] || [relative.pathExtension isEqual:@"app"]) {
            [result addObject:[app stringByAppendingPathComponent:relative]];
        }
    }
    return [result sortedArrayUsingSelector:@selector(compare:)];
}

static NSString *WGUnsupportedEntitlement(NSDictionary *entitlements, NSDictionary *allowed) {
    for (NSString *key in [[entitlements allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        id value = entitlements[key];
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() && ![value boolValue]) continue;
        if (!WGAllowed(value, allowed[key])) return key;
    }
    return nil;
}

static NSArray<NSDictionary *> *WGSigningPlan(NSString *app, NSData *cert, NSArray<NSData *> *imported, NSError **error) {
    NSArray<NSString *> *bundles = WGBundles(app);
    NSMutableArray<NSData *> *data = [imported mutableCopy];
    for (NSString *bundle in bundles) {
        NSData *embedded = [NSData dataWithContentsOfFile:[bundle stringByAppendingPathComponent:@"embedded.mobileprovision"]];
        if (embedded && ![data containsObject:embedded]) [data addObject:embedded];
    }
    NSMutableArray<NSDictionary *> *candidates = [NSMutableArray new];
    for (NSData *bytes in data) {
        NSDictionary *profile = WGProfile(bytes);
        if ([profile[@"Entitlements"] isKindOfClass:NSDictionary.class] &&
            [profile[@"ExpirationDate"] isKindOfClass:NSDate.class] &&
            [profile[@"DeveloperCertificates"] isKindOfClass:NSArray.class]) {
            [candidates addObject:@{@"data": bytes, @"profile": profile}];
        }
    }
    NSMutableArray<NSDictionary *> *plan = [NSMutableArray new];
    for (NSString *bundle in bundles) {
        NSString *name = bundle.length == app.length ? app.lastPathComponent : [bundle substringFromIndex:app.length + 1];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]];
        NSString *bundleId = info[@"CFBundleIdentifier"], *exe = info[@"CFBundleExecutable"];
        if (![bundleId isKindOfClass:NSString.class] || ![exe isKindOfClass:NSString.class] ||
            ![cert isEqual:WGInstalledCertificate([bundle stringByAppendingPathComponent:exe])]) {
            WGFail(error, 2); return nil;
        }
        NSData *entitlementData = WGSignatureSlot([bundle stringByAppendingPathComponent:exe], 5);
        NSDictionary *entitlements = entitlementData ? [NSPropertyListSerialization propertyListWithData:entitlementData options:NSPropertyListImmutable format:nil error:nil] : nil;
        if (![entitlements isKindOfClass:NSDictionary.class] ||
            ![entitlements[@"application-identifier"] isKindOfClass:NSString.class] ||
            [entitlements[@"application-identifier"] length] == 0) {
            WGProfileFail(error, @"installedEntitlements", name); return nil;
        }
        NSString *reason = data.count == 0 ? @"missing" : @"unreadable";
        NSInteger bestRank = 0;
        NSString *unsupported = @"";
        NSData *selected = nil;
        NSDate *latest = NSDate.distantPast;
        for (NSDictionary *candidate in candidates) {
            NSDictionary *profile = candidate[@"profile"], *allowed = profile[@"Entitlements"];
            NSDate *expiry = profile[@"ExpirationDate"];
            NSInteger rank = 1; NSString *issue = @"expired", *key = @"";
            if ([expiry compare:NSDate.date] == NSOrderedDescending) {
                rank = 2; issue = @"certificate";
                if ([profile[@"DeveloperCertificates"] containsObject:cert]) {
                    rank = 3; issue = @"applicationIdentifier";
                    if (WGAllowed(entitlements[@"application-identifier"], allowed[@"application-identifier"])) {
                        rank = 4; issue = @"entitlement";
                        key = WGUnsupportedEntitlement(entitlements, allowed);
                        if (!key) {
                            if ([expiry compare:latest] == NSOrderedDescending) { selected = candidate[@"data"]; latest = expiry; }
                            continue;
                        }
                    }
                }
            }
            if (rank > bestRank) { bestRank = rank; reason = issue; unsupported = key; }
        }
        if (!selected) { WGProfileFail(error, reason, name, unsupported); return nil; }
        [plan addObject:@{@"bundle": bundle, @"info": info, @"entitlements": entitlements, @"profile": selected}];
    }
    return plan;
}

@interface WGUpdateArchiveGuard : NSObject <SSZipArchiveDelegate>
@property(nonatomic) BOOL invalid;
@end
@implementation WGUpdateArchiveGuard
- (BOOL)zipArchiveShouldUnzipFileAtIndex:(NSInteger)index totalFiles:(NSInteger)total archivePath:(NSString *)path fileInfo:(unz_file_info)info {
    // WyGram's device release has no symlinks. Refuse them before extraction writes any link.
    if (((info.external_fa >> 16) & 0170000) == 0120000 || total > 100000) { self.invalid = YES; return NO; }
    return YES;
}
@end

static NSString *WGUnpackUpdate(NSString *ipa, NSString *work, NSString *version, NSString *build, NSError **error) {
    NSArray<SSZipEntry *> *entries = [SSZipArchive getEntriesForFileAtPath:ipa];
    if (!entries || entries.count == 0 || entries.count > 100000) { WGFail(error, 4); return nil; }
    uint64_t total = 0;
    for (SSZipEntry *entry in entries) {
        NSString *path = entry.path;
        if ([path hasPrefix:@"/"] || [path containsString:@"\\"] || [path.pathComponents containsObject:@".."] || [path containsString:@"\0"]) { WGFail(error, 4); return nil; }
        total += entry.uncompressedSize;
        if (total > 1500ULL * 1024 * 1024) { WGFail(error, 4); return nil; }
    }
    WGUpdateArchiveGuard *guard = [WGUpdateArchiveGuard new];
    if (![SSZipArchive unzipFileAtPath:ipa toDestination:work delegate:guard] || guard.invalid) { WGFail(error, 4); return nil; }
    NSString *payload = [work stringByAppendingPathComponent:@"Payload"];
    NSArray *apps = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:payload error:nil] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.app'"]];
    if (apps.count != 1) { WGFail(error, 4); return nil; }
    NSString *app = [payload stringByAppendingPathComponent:apps[0]];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[app stringByAppendingPathComponent:@"Info.plist"]];
    if (![info[@"CFBundleShortVersionString"] isEqual:version] || ![[info[@"CFBundleVersion"] description] isEqual:build]) { WGFail(error, 5); return nil; }
    return app;
}

@implementation WGUpdateSigner
+ (BOOL)validateTrollStoreIPA:(NSString *)ipa installedApp:(NSString *)installedApp expectedVersion:(NSString *)version expectedBuild:(NSString *)build error:(NSError **)error {
    std::lock_guard<std::mutex> lock(signerMutex);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *work = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if (![fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionComplete} error:nil]) return WGFail(error, 4);
    @try {
        NSString *app = WGUnpackUpdate(ipa, work, version, build, error);
        if (!app) return NO;
        NSArray<NSString *> *installed = WGBundles(installedApp), *downloaded = WGBundles(app);
        if (installed.count != downloaded.count) return WGFail(error, 5);
        for (NSString *bundle in installed) {
            NSString *relative = bundle.length == installedApp.length ? @"" : [bundle substringFromIndex:installedApp.length + 1];
            NSString *target = relative.length ? [app stringByAppendingPathComponent:relative] : app;
            if (![downloaded containsObject:target]) return WGFail(error, 5);
            NSDictionary *current = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]];
            NSDictionary *next = [NSDictionary dictionaryWithContentsOfFile:[target stringByAppendingPathComponent:@"Info.plist"]];
            for (NSString *key in @[@"CFBundleIdentifier", @"CFBundleExecutable", @"TelegramApplicationGroupIdentifier"]) {
                if (![current[key] isEqual:next[key]] && (current[key] || next[key])) return WGFail(error, 5);
            }
            for (NSDictionary *info in @[current ?: @{}, next ?: @{}]) {
                if (![info[@"CFBundleIdentifier"] isKindOfClass:NSString.class] || ![info[@"CFBundleExecutable"] isKindOfClass:NSString.class]) return WGFail(error, 4);
            }
            NSData *currentData = WGSignatureSlot([bundle stringByAppendingPathComponent:current[@"CFBundleExecutable"]], 5);
            NSData *nextData = WGSignatureSlot([target stringByAppendingPathComponent:next[@"CFBundleExecutable"]], 5);
            NSDictionary *currentRights = currentData ? [NSPropertyListSerialization propertyListWithData:currentData options:NSPropertyListImmutable format:nil error:nil] : nil;
            NSDictionary *nextRights = nextData ? [NSPropertyListSerialization propertyListWithData:nextData options:NSPropertyListImmutable format:nil error:nil] : nil;
            if (![currentRights isKindOfClass:NSDictionary.class] || ![nextRights isKindOfClass:NSDictionary.class]) return WGFail(error, 5);
            for (NSString *key in @[@"com.apple.security.application-groups", @"keychain-access-groups"]) {
                if (![currentRights[key] isEqual:nextRights[key]] && (currentRights[key] || nextRights[key])) return WGFail(error, 5);
            }
        }
        return YES;
    } @finally { [fm removeItemAtPath:work error:nil]; }
}

+ (NSArray<NSData *> *)installedProfiles:(NSString *)installedApp certificate:(NSData *)p12 password:(NSString *)password error:(NSError **)error {
    std::lock_guard<std::mutex> lock(signerMutex);
    ZLog::SetLogLever(ZLog::E_NONE);
    NSData *cert = WGCertificate(p12, password);
    if (!cert) { WGFail(error, 1); return nil; }
    NSMutableArray<NSData *> *result = [NSMutableArray new];
    for (NSString *bundle in WGBundles(installedApp)) {
        NSData *data = [NSData dataWithContentsOfFile:[bundle stringByAppendingPathComponent:@"embedded.mobileprovision"]];
        if (!data || [result containsObject:data]) continue;
        NSDictionary *profile = WGProfile(data);
        NSDate *expiry = profile[@"ExpirationDate"];
        if (![expiry isKindOfClass:NSDate.class] || [expiry compare:NSDate.date] != NSOrderedDescending ||
            ![profile[@"DeveloperCertificates"] isKindOfClass:NSArray.class] || ![profile[@"DeveloperCertificates"] containsObject:cert]) continue;
        [result addObject:data];
    }
    return result;
}

+ (BOOL)validateProfiles:(NSArray<NSData *> *)profiles error:(NSError **)error {
    std::lock_guard<std::mutex> lock(signerMutex);
    ZLog::SetLogLever(ZLog::E_NONE);
    for (NSData *data in profiles) {
        NSDictionary *profile = WGProfile(data);
        if (![profile[@"Entitlements"] isKindOfClass:NSDictionary.class] ||
            ![profile[@"ExpirationDate"] isKindOfClass:NSDate.class] ||
            ![profile[@"DeveloperCertificates"] isKindOfClass:NSArray.class] ||
            ![profile[@"TeamIdentifier"] isKindOfClass:NSArray.class] || [profile[@"TeamIdentifier"] count] == 0) {
            return WGProfileFail(error, @"unreadable", @"");
        }
        NSDate *expiry = profile[@"ExpirationDate"];
        if ([expiry compare:NSDate.date] != NSOrderedDescending) return WGProfileFail(error, @"expired", @"");
    }
    return YES;
}

+ (BOOL)validateInstalledApp:(NSString *)installedApp certificate:(NSData *)p12 password:(NSString *)password profiles:(NSArray<NSData *> *)profiles error:(NSError **)error {
    std::lock_guard<std::mutex> lock(signerMutex);
    ZLog::SetLogLever(ZLog::E_NONE);
    NSData *cert = WGCertificate(p12, password);
    if (!cert) return WGFail(error, 1);
    return WGSigningPlan(installedApp, cert, profiles, error) != nil;
}

+ (NSString *)validateCertificate:(NSData *)p12 password:(NSString *)password installedApp:(NSString *)installedApp error:(NSError **)error {
    std::lock_guard<std::mutex> lock(signerMutex);
    ZLog::SetLogLever(ZLog::E_NONE);
    NSData *cert = WGCertificate(p12, password);
    if (!cert) { WGFail(error, 1); return nil; }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[installedApp stringByAppendingPathComponent:@"Info.plist"]];
    NSString *exe = info[@"CFBundleExecutable"];
    if (![exe isKindOfClass:NSString.class] || ![cert isEqual:WGInstalledCertificate([installedApp stringByAppendingPathComponent:exe])]) { WGFail(error, 2); return nil; }
    const unsigned char *p = (const unsigned char *)cert.bytes;
    X509 *x509 = d2i_X509(nullptr, &p, (long)cert.length);
    char name[512] = {0};
    X509_NAME_get_text_by_NID(X509_get_subject_name(x509), NID_commonName, name, sizeof(name));
    X509_free(x509);
    return [NSString stringWithUTF8String:name] ?: @"Certificate";
}

+ (BOOL)prepareIPA:(NSString *)ipa output:(NSString *)output installedApp:(NSString *)installedApp certificate:(NSData *)p12 password:(NSString *)password profiles:(NSArray<NSData *> *)profiles expectedVersion:(NSString *)version expectedBuild:(NSString *)build error:(NSError **)error {
    std::lock_guard<std::mutex> lock(signerMutex);
    ZLog::SetLogLever(ZLog::E_NONE);
    NSData *cert = WGCertificate(p12, password);
    if (!cert) return WGFail(error, 1);
    NSString *work = [output.stringByDeletingLastPathComponent stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:work withIntermediateDirectories:YES attributes:@{NSFileProtectionKey:NSFileProtectionComplete} error:nil]) return WGFail(error, 4);
    @try {
        NSString *app = WGUnpackUpdate(ipa, work, version, build, error);
        if (!app) return NO;
        NSString *payload = [work stringByAppendingPathComponent:@"Payload"];
        NSArray<NSString *> *installed = WGBundles(installedApp), *downloaded = WGBundles(app);
        if (installed.count != downloaded.count) return WGFail(error, 5);
        NSArray<NSDictionary *> *plan = WGSigningPlan(installedApp, cert, profiles, error);
        if (!plan) return NO;
        NSString *keyPath = [work stringByAppendingPathComponent:@"identity.p12"];
        if (![p12 writeToFile:keyPath options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:nil]) return WGFail(error, 1);
        std::list<ZSignAsset> assets;
        NSUInteger index = 0;
        for (NSDictionary *entry in plan) {
            NSString *bundle = entry[@"bundle"];
            NSString *relative = bundle.length == installedApp.length ? @"" : [bundle substringFromIndex:installedApp.length + 1];
            NSString *target = relative.length ? [app stringByAppendingPathComponent:relative] : app;
            if (![downloaded containsObject:target]) return WGFail(error, 5);
            NSDictionary *info = entry[@"info"];
            NSString *bundleId = info[@"CFBundleIdentifier"], *exe = info[@"CFBundleExecutable"];
            NSDictionary *entitlements = entry[@"entitlements"];
            NSData *selected = entry[@"profile"];
            NSString *profilePath = [work stringByAppendingPathComponent:[NSString stringWithFormat:@"profile-%lu.mobileprovision", (unsigned long)index]];
            NSString *entitlementPath = [work stringByAppendingPathComponent:[NSString stringWithFormat:@"entitlements-%lu.plist", (unsigned long)index++]];
            NSData *xml = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
            if (![selected writeToFile:profilePath atomically:YES] || ![xml writeToFile:entitlementPath atomically:YES]) return WGFail(error, 3);
            assets.emplace_back();
            ZSignAsset &asset = assets.back();
            if (!asset.Init("", keyPath.UTF8String, profilePath.UTF8String, entitlementPath.UTF8String, password.UTF8String, false, false, false)) return WGFail(error, 6);
            // Use the actual bundle ID to route each signing asset. The existing
            // application-identifier belongs in the preserved entitlements;
            // sideloading tools can choose it independently of the plist ID.
            asset.m_strApplicationId = [bundleId UTF8String];
            NSMutableDictionary *targetInfo = [[NSDictionary dictionaryWithContentsOfFile:[target stringByAppendingPathComponent:@"Info.plist"]] mutableCopy];
            if (!targetInfo || ![targetInfo[@"CFBundleExecutable"] isEqual:exe]) return WGFail(error, 5);
            targetInfo[@"CFBundleIdentifier"] = bundleId;
            // Carry the installer's app-group and URL-scheme choices across upgrades.
            for (NSString *field in @[@"TelegramApplicationGroupIdentifier", @"CFBundleURLTypes", @"CFBundleDisplayName"]) {
                if (info[field]) targetInfo[field] = info[field];
            }
            if (![targetInfo writeToFile:[target stringByAppendingPathComponent:@"Info.plist"] atomically:YES]) return WGFail(error, 5);
        }
        ZBundle signer;
        if (!signer.SignFolder(&assets, app.UTF8String, "", "", "", {}, {}, true, false, false)) return WGFail(error, 6);
        for (NSString *target in downloaded) {
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[target stringByAppendingPathComponent:@"Info.plist"]];
            if (![cert isEqual:WGInstalledCertificate([target stringByAppendingPathComponent:info[@"CFBundleExecutable"]])]) return WGFail(error, 6);
        }
        NSString *packed = [work stringByAppendingPathComponent:@"package"];
        if (![fm createDirectoryAtPath:packed withIntermediateDirectories:YES attributes:nil error:nil] || ![fm moveItemAtPath:payload toPath:[packed stringByAppendingPathComponent:@"Payload"] error:nil]) return WGFail(error, 4);
        [fm removeItemAtPath:output error:nil];
        if (![SSZipArchive createZipFileAtPath:output withContentsOfDirectory:packed]) return WGFail(error, 4);
        return YES;
    } @finally {
        [fm removeItemAtPath:work error:nil];
        ERR_clear_error();
    }
}
@end
