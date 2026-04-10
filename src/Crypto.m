#import "Crypto.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>
#import <string.h>

NSErrorDomain const FileLockErrorDomain = @"com.filelock";

/*
 * 파일 포맷 v2:
 *   magic(4) | version(1) | saltAES(32) | saltMAC(32) | IV(16) | HMAC(32) | ciphertext
 *
 * - magic   : 'F','L',0x01,0xA7  — 손상 파일 조기 감지
 * - version : 0x02               — 포맷 버전 (업그레이드 대비)
 * - saltAES : AES 키 유도 전용 솔트 (도메인 분리)
 * - saltMAC : MAC 키 유도 전용 솔트 (도메인 분리)
 * - IV      : AES-256-CBC 초기화 벡터
 * - HMAC    : HMAC-SHA256 over (magic|version|saltAES|saltMAC|IV|ciphertext)
 * - PBKDF2  : 300,000 iterations, SHA-256
 * - 키 소거 : memset_s (컴파일러 최적화로 삭제되지 않음)
 */

enum {
    kSaltAES = 32,
    kSaltMAC = 32,
    kIV      = 16,
    kHMAC    = 32,
    kAESKey  = 32,
    kMACKey  = 32,
    kIters   = 300000,

    kMagicLen   = 4,
    kVersionLen = 1,
    // 헤더 = magic + version + saltAES + saltMAC + IV + HMAC
    kHead = (kMagicLen + kVersionLen + kSaltAES + kSaltMAC + kIV + kHMAC),  // 117
};

static const uint8_t kMagic[kMagicLen]     = {'F', 'L', 0x01, 0xA7};
static const uint8_t kVersion[kVersionLen] = {0x02};

// 도메인 레이블 — 솔트에 혼합해 키 유도 도메인 분리
static const char kLabelAES[] = "FileLock-AES";
static const char kLabelMAC[] = "FileLock-MAC";

// ── 키 유도 ────────────────────────────────────────────────
// 솔트와 도메인 레이블을 결합 → PBKDF2 → 32바이트 키 1개
static BOOL deriveKey(NSString *pw,
                      const uint8_t *salt, size_t saltLen,
                      const char *label, size_t labelLen,
                      uint8_t outKey[32]) {
    // combined_salt = salt ‖ label
    size_t cs = saltLen + labelLen;
    uint8_t *combinedSalt = (uint8_t *)malloc(cs);
    if (!combinedSalt) return NO;
    memcpy(combinedSalt,           salt,  saltLen);
    memcpy(combinedSalt + saltLen, label, labelLen);

    const char *c = pw.UTF8String;
    CCStatus st = CCKeyDerivationPBKDF(kCCPBKDF2, c, strlen(c),
                                       combinedSalt, cs,
                                       kCCPRFHmacAlgSHA256, kIters,
                                       outKey, 32);
    memset_s(combinedSalt, cs, 0, cs);
    free(combinedSalt);
    return st == kCCSuccess;
}

// ── HMAC-SHA256 ────────────────────────────────────────────
// header = magic ‖ version ‖ saltAES ‖ saltMAC ‖ IV
// HMAC over (header ‖ ciphertext)
static void computeMAC(const uint8_t macKey[kMACKey],
                       const uint8_t *header, size_t hdrLen,
                       const uint8_t *ct, size_t ctLen,
                       uint8_t out[kHMAC]) {
    CCHmacContext ctx;
    CCHmacInit  (&ctx, kCCHmacAlgSHA256, macKey, kMACKey);
    CCHmacUpdate(&ctx, header, hdrLen);
    CCHmacUpdate(&ctx, ct,     ctLen);
    CCHmacFinal (&ctx, out);
    memset_s(&ctx, sizeof(ctx), 0, sizeof(ctx));
}

// ── 상수 시간 비교 ─────────────────────────────────────────
static BOOL safeEq(const uint8_t *a, const uint8_t *b, size_t n) {
    volatile uint8_t diff = 0;
    for (size_t i = 0; i < n; i++) diff |= (a[i] ^ b[i]);
    return diff == 0;
}

// ── 암호화 ────────────────────────────────────────────────
NSData *FL_Encrypt(NSData *plain, NSString *password, NSError **err) {
    // 1) 난수: saltAES, saltMAC, IV
    uint8_t saltAES[kSaltAES], saltMAC[kSaltMAC], iv[kIV];
    if (SecRandomCopyBytes(kSecRandomDefault, kSaltAES, saltAES) != errSecSuccess ||
        SecRandomCopyBytes(kSecRandomDefault, kSaltMAC, saltMAC) != errSecSuccess ||
        SecRandomCopyBytes(kSecRandomDefault, kIV,      iv)      != errSecSuccess) {
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorIO
                                       userInfo:@{NSLocalizedDescriptionKey:@"난수 생성 실패"}];
        return nil;
    }

    // 2) 분리된 키 유도
    uint8_t aesKey[kAESKey], macKey[kMACKey];
    if (!deriveKey(password, saltAES, kSaltAES, kLabelAES, sizeof(kLabelAES)-1, aesKey) ||
        !deriveKey(password, saltMAC, kSaltMAC, kLabelMAC, sizeof(kLabelMAC)-1, macKey)) {
        memset_s(aesKey, kAESKey, 0, kAESKey);
        memset_s(macKey, kMACKey, 0, kMACKey);
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorIO
                                       userInfo:@{NSLocalizedDescriptionKey:@"키 유도 실패"}];
        return nil;
    }

    // 3) AES-256-CBC 암호화
    size_t ctCap = plain.length + kCCBlockSizeAES128;
    NSMutableData *ct = [NSMutableData dataWithLength:ctCap];
    size_t ctLen = 0;
    CCCryptorStatus st = CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 aesKey, kAESKey, iv,
                                 plain.bytes, plain.length,
                                 ct.mutableBytes, ctCap, &ctLen);
    memset_s(aesKey, kAESKey, 0, kAESKey);

    if (st != kCCSuccess) {
        memset_s(macKey, kMACKey, 0, kMACKey);
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorIO
                                       userInfo:@{NSLocalizedDescriptionKey:@"암호화 실패"}];
        return nil;
    }
    ct.length = ctLen;

    // 4) 헤더 구성 (HMAC 계산용): magic | version | saltAES | saltMAC | IV
    size_t hdrPreLen = kMagicLen + kVersionLen + kSaltAES + kSaltMAC + kIV;  // 85
    uint8_t hdrPre[85];
    size_t off = 0;
    memcpy(hdrPre + off, kMagic,   kMagicLen);   off += kMagicLen;
    memcpy(hdrPre + off, kVersion, kVersionLen);  off += kVersionLen;
    memcpy(hdrPre + off, saltAES,  kSaltAES);     off += kSaltAES;
    memcpy(hdrPre + off, saltMAC,  kSaltMAC);     off += kSaltMAC;
    memcpy(hdrPre + off, iv,       kIV);

    // 5) HMAC-SHA256 over (header_pre ‖ ciphertext)
    uint8_t hmac[kHMAC];
    computeMAC(macKey, hdrPre, hdrPreLen, (const uint8_t*)ct.bytes, ctLen, hmac);
    memset_s(macKey, kMACKey, 0, kMACKey);

    // 6) 최종 출력: header_pre | HMAC | ciphertext
    NSMutableData *out = [NSMutableData dataWithCapacity:kHead + ctLen];
    [out appendBytes:hdrPre length:hdrPreLen];
    [out appendBytes:hmac   length:kHMAC];
    [out appendData:ct];
    return out;
}

// ── 복호화 ────────────────────────────────────────────────
NSData *FL_Decrypt(NSData *blob, NSString *password, NSError **err) {
    if ((NSInteger)blob.length <= kHead) {
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorWrongPassword
                                       userInfo:@{NSLocalizedDescriptionKey:@"잘못된 비밀번호"}];
        return nil;
    }

    const uint8_t *b = (const uint8_t*)blob.bytes;

    // 1) 매직 + 버전 검증
    if (memcmp(b, kMagic, kMagicLen) != 0 || b[kMagicLen] != kVersion[0]) {
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorWrongPassword
                                       userInfo:@{NSLocalizedDescriptionKey:@"잘못된 비밀번호"}];
        return nil;
    }

    // 2) 헤더 파싱
    size_t off = 0;
    const uint8_t *magic   = b + off; off += kMagicLen;    // 사용 완료 (위에서 검증)
    (void)magic;
    const uint8_t *ver     = b + off; off += kVersionLen;  (void)ver;
    const uint8_t *saltAES = b + off; off += kSaltAES;
    const uint8_t *saltMAC = b + off; off += kSaltMAC;
    const uint8_t *iv      = b + off; off += kIV;
    const uint8_t *hmac    = b + off; off += kHMAC;
    const uint8_t *ct      = b + off;
    size_t ctLen           = blob.length - off;

    size_t hdrPreLen = kMagicLen + kVersionLen + kSaltAES + kSaltMAC + kIV;  // 85

    // 3) 분리된 키 유도
    uint8_t aesKey[kAESKey], macKey[kMACKey];
    if (!deriveKey(password, saltAES, kSaltAES, kLabelAES, sizeof(kLabelAES)-1, aesKey) ||
        !deriveKey(password, saltMAC, kSaltMAC, kLabelMAC, sizeof(kLabelMAC)-1, macKey)) {
        memset_s(aesKey, kAESKey, 0, kAESKey);
        memset_s(macKey, kMACKey, 0, kMACKey);
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorIO
                                       userInfo:@{NSLocalizedDescriptionKey:@"키 유도 실패"}];
        return nil;
    }

    // 4) HMAC 검증 (상수 시간)
    uint8_t expected[kHMAC];
    computeMAC(macKey, b, hdrPreLen, ct, ctLen, expected);
    memset_s(macKey, kMACKey, 0, kMACKey);

    if (!safeEq(expected, hmac, kHMAC)) {
        memset_s(aesKey, kAESKey, 0, kAESKey);
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorWrongPassword
                                       userInfo:@{NSLocalizedDescriptionKey:@"잘못된 비밀번호"}];
        return nil;
    }

    // 5) AES-256-CBC 복호화
    size_t ptCap = ctLen + kCCBlockSizeAES128;
    NSMutableData *plain = [NSMutableData dataWithLength:ptCap];
    size_t ptLen = 0;
    CCCryptorStatus cst = CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                  aesKey, kAESKey, iv,
                                  ct, ctLen,
                                  plain.mutableBytes, ptCap, &ptLen);
    memset_s(aesKey, kAESKey, 0, kAESKey);

    if (cst != kCCSuccess) {
        if (err) *err = [NSError errorWithDomain:FileLockErrorDomain
                                           code:FileLockErrorWrongPassword
                                       userInfo:@{NSLocalizedDescriptionKey:@"잘못된 비밀번호"}];
        return nil;
    }
    plain.length = ptLen;
    return plain;
}
