@isTest
public class DataEncryptorTest {
    @isTest
    static void testEncryptDecrypt() {        
        String originalText = 'This is a test string for encryption.';
        String privateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        String hmacKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        AdaWalletsService.setPrivateKey(privateKey);
        AdaWalletsService.setHmacKey(hmacKey);
        
        String encryptedText = DataEncryptor.encrypt(originalText);
        String decryptedText = DataEncryptor.decrypt(encryptedText);
        
        Assert.areNotEqual(encryptedText, originalText, 'Encrypted text should not be the same as the original text.');
        Assert.areEqual(originalText, decryptedText, 'Decrypted text should match the original text.');
    }

    @isTest
    static void testEncryptWithNull() {        
        String privateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        String hmacKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        AdaWalletsService.setPrivateKey(privateKey);
        AdaWalletsService.setHmacKey(hmacKey);
        Boolean exceptionThrown = false;

        try {
            DataEncryptor.encrypt(null);
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Assert.isTrue(exceptionThrown, 'Expected an exception when encrypting null.');
    }

    @isTest
    static void testDecryptWithInvalidData() {        
        String privateKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        String hmacKey = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        AdaWalletsService.setPrivateKey(privateKey);
        AdaWalletsService.setHmacKey(hmacKey);
        Boolean exceptionThrown = false;
        
        try {
            DataEncryptor.decrypt('InvalidBase64String');
        } catch (Exception e) {
            exceptionThrown = true;
        }
        Assert.isTrue(exceptionThrown, 'Expected an exception when decrypting invalid data.');
    }
}