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
        
        Blob data = Blob.valueOf(plainText);
        Blob encrypted = Crypto.encryptWithManagedIV('AES128', getEncryptionKey(), data);        
        return EncodingUtil.base64Encode(encrypted);
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
}