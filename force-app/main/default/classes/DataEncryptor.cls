public with sharing class DataEncryptor {    
    private static Blob key = EncodingUtil.convertFromHex(AdaWalletsService.getPrivateKey());    

    public static String encrypt(String plainText) {        
        Blob data = Blob.valueOf(plainText);
        Blob encrypted = Crypto.encryptWithManagedIV('AES128', key, data);        
        return EncodingUtil.base64Encode(encrypted);
    }

    public static String decrypt(String encryptedText) {        
        Blob encrypted = EncodingUtil.base64Decode(encryptedText);
        Blob decrypted = Crypto.decryptWithManagedIV('AES128', key, encrypted);
        return decrypted.toString();
    }
}