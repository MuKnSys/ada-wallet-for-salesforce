public with sharing class AdaWalletsService {
    private static AdaSettings__c adaSettings;
    private static final String KEY_ALREADY_SET_ERROR = 'Encryption key is already set and cannot be changed for security reasons';

    private static AdaSettings__c getSettings() {
        if (adaSettings == null) {
            adaSettings = AdaSettings__c.getOrgDefaults();
        }
        return adaSettings;
    }

    public static String getPrivateKey() {
        AdaSettings__c adaSettings = getSettings();
        return adaSettings.Private_Key__c != null ? adaSettings.Private_Key__c : '';
    }

    public static String getBlockfrostProjectId() {
        AdaSettings__c adaSettings = getSettings();
        return adaSettings.BlockfrostProjectId__c != null ? adaSettings.BlockfrostProjectId__c : '';
    }

    public static void setPrivateKey(String key) {
        AdaSettings__c adaSettings = getSettings();
        
        // Immutable check: prevent key changes if already set
        if (String.isNotBlank(adaSettings.Private_Key__c)) {
            throw new SecurityException(KEY_ALREADY_SET_ERROR);
        }
        
        // Validate key length (32 characters = 128 bits)
        if (String.isBlank(key) || key.length() != 32) {
            throw new IllegalArgumentException('Encryption key must be exactly 32 characters (128 bits)');
        }
        
        adaSettings.Private_Key__c = key;
        upsert adaSettings;
    }

    public static void setBlockfrostProjectId(String blockfrostProjectId) {
        AdaSettings__c adaSettings = getSettings();
        adaSettings.BlockfrostProjectId__c = blockfrostProjectId;
        upsert adaSettings;
    }
    
    public static Boolean isEncryptionKeySet() {
        AdaSettings__c adaSettings = getSettings();
        return String.isNotBlank(adaSettings.Private_Key__c);
    }
    
    public static void validateEncryptionKey() {
        if (!isEncryptionKeySet()) {
            throw new SecurityException('Encryption key is not configured. Please set up the encryption key first.');
        }
    }
}
