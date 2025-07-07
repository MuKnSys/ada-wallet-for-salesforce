public with sharing class DataEncryptor {    
    private static Blob key;

    private static Blob getEncryptionKey() {
        if (key == null) {
            AdaWalletsService.validateEncryptionKey();
            key = EncodingUtil.convertFromHex(AdaWalletsService.getPrivateKey());
        }
        return key;
    }

    @AuraEnabled
    public static String encrypt(String plainText) {
        if (String.isBlank(plainText)) {
            throw new IllegalArgumentException('Plain text cannot be null or empty');
        }
        
        // Use AES encryption for reversible storage (for private keys, etc.)
        Blob data = Blob.valueOf(plainText);
        Blob encrypted = Crypto.encryptWithManagedIV('AES128', getEncryptionKey(), data);        
        return EncodingUtil.base64Encode(encrypted);
    }

    @AuraEnabled
    public static String encryptHmac(String plainText) {
        if (String.isBlank(plainText)) {
            throw new IllegalArgumentException('Plain text cannot be null or empty');
        }
        
        // Use HMAC for deterministic and secure verification (for seed phrases)
        Blob hmac = Crypto.generateMac('HmacSHA256', Blob.valueOf(plainText), getEncryptionKey());
        return EncodingUtil.base64Encode(hmac);
    }


    @AuraEnabled
    public static String decrypt(String encryptedText) {
        if (String.isBlank(encryptedText)) {
            throw new IllegalArgumentException('Encrypted text cannot be null or empty');
        }
        
        Blob encrypted = EncodingUtil.base64Decode(encryptedText);
        Blob decrypted = Crypto.decryptWithManagedIV('AES128', getEncryptionKey(), encrypted);
        return decrypted.toString();
    }

    /**
     * Note: HMAC is not reversible, so decrypt method is not available for HMAC values
     * Use verifyHmac method instead for verification
     */
    @AuraEnabled
    public static Boolean verifyHmac(String plainText, String hmacValue) {
        if (String.isBlank(plainText) || String.isBlank(hmacValue)) {
            return false;
        }
        
        try {
            String calculatedHmac = encryptHmac(plainText);
            return calculatedHmac == hmacValue;
        } catch (Exception e) {
            return false;
        }
    }
}