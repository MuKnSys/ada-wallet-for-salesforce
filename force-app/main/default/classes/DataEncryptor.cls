public with sharing class DataEncryptor {
    private static Blob encryptionKey;
    private static Blob hmacKey;

    private static Blob getEncryptionKey() {
        if (encryptionKey == null) {
            AdaWalletsService.validateEncryptionKey();
            encryptionKey = EncodingUtil.base64Decode(AdaWalletsService.getPrivateKey());
        }
        return encryptionKey;
    }

    private static Blob getHmacKey() {
        if (hmacKey == null) {
            AdaWalletsService.validateEncryptionKey();
            hmacKey = EncodingUtil.base64Decode(AdaWalletsService.getHmacKey());
        }
        return hmacKey;
    }

    @AuraEnabled
    public static String encrypt(String plainText) {
        if (String.isBlank(plainText)) {
            throw new IllegalArgumentException('Plain text cannot be null or empty');
        }

        String encryptedValue = EncodingUtil.base64Encode(Crypto.encryptWithManagedIV('AES256', getEncryptionKey(), Blob.valueOf(plainText)));
        String hmacValue = EncodingUtil.base64Encode(Crypto.generateMac('HmacSHA256', Blob.valueOf(encryptedValue), getHmacKey()));
        return hmacValue + encryptedValue;
    }

    @AuraEnabled
    public static String decrypt(String encryptedText) {
        if (String.isBlank(encryptedText)) {
            throw new IllegalArgumentException('Encrypted text cannot be null or empty');
        }

        try {
            String hmacValue = encryptedText.substring(0, 44);
            String encryptedValue = encryptedText.substring(44);

            Boolean verified = Crypto.verifyHMac('HmacSHA256', Blob.valueOf(encryptedValue), getHmacKey(), EncodingUtil.base64Decode(hmacValue));
            if (!verified) {
                throw new IllegalArgumentException('HMAC verification failed - data may have been tampered with');
            }

            Blob encrypted = EncodingUtil.base64Decode(encryptedValue);
            Blob decrypted = Crypto.decryptWithManagedIV('AES256', getEncryptionKey(), encrypted);
            return decrypted.toString();
        } catch (Exception e) {
            throw new IllegalArgumentException('Failed to decrypt data: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static String encryptHmac(String plainText) {
        if (String.isBlank(plainText)) {
            throw new IllegalArgumentException('Plain text cannot be null or empty');
        }

        // Use HMAC for deterministic and secure verification (for seed phrases)
        Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(plainText), getHmacKey());
        return EncodingUtil.base64Encode(hmac);
    }

    @AuraEnabled
    public static Boolean verifyHmac(String plainText, String hmacValue) {
        if (String.isBlank(plainText) || String.isBlank(hmacValue)) {
            return false;
        }

        try {
            Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(plainText), getHmacKey());
            String calculatedHmac = EncodingUtil.base64Encode(hmac);
            return calculatedHmac == hmacValue;
        } catch (Exception e) {
            return false;
        }
    }
}