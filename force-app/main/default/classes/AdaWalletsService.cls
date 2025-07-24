public with sharing class AdaWalletsService {
    private static AdaSettings__c adaSettings;
    private static final String PRIVATE_KEY_ALREADY_SET_ERROR = 'Encryption key is already set and cannot be changed for security reasons';
    private static final String HMAC_KEY_ALREADY_SET_ERROR = 'Hmac key is already set and cannot be changed for security reasons';

    private static AdaSettings__c getSettings() {
        if (adaSettings == null) {
            adaSettings = AdaSettings__c.getOrgDefaults();
        }
        return adaSettings;
    }

    public static String getPrivateKey() {
        if (!hasRequiredPermissions()) {
            throw new SecurityException('Access denied: insufficient permissions to access encryption key');
        }
        
        AdaSettings__c adaSettings = getSettings();
        return adaSettings.Private_Key__c != null ? adaSettings.Private_Key__c : '';
    }

    public static String getHmacKey() {
        if (!hasRequiredPermissions()) {
            throw new SecurityException('Access denied: insufficient permissions to access encryption key');
        }
        
        AdaSettings__c adaSettings = getSettings();
        return adaSettings.Hmac_Key__c != null ? adaSettings.Hmac_Key__c : '';
    }

    public static String getBlockfrostProjectId() {
        AdaSettings__c adaSettings = getSettings();
        return adaSettings.BlockfrostProjectId__c != null ? adaSettings.BlockfrostProjectId__c : '';
    }

    public static void setPrivateKey(String key) {
        AdaSettings__c adaSettings = getSettings();
        
        // Immutable check: prevent key changes if already set
        if (String.isNotBlank(adaSettings.Private_Key__c)) {
            throw new SecurityException(PRIVATE_KEY_ALREADY_SET_ERROR);
        }
        
        if (String.isBlank(key)) {
            throw new IllegalArgumentException('Private key must not be blank');
        }

        Blob keyBlob;
        try {
            keyBlob = EncodingUtil.base64Decode(key);
        } catch(Exception e) {
            throw new IllegalArgumentException('Private key is not valid Base64');
        }

        if (keyBlob.size() != 32) {
            throw new IllegalArgumentException('Private key must be exactly 32 bytes (256 bits)');
        }
        
        adaSettings.Private_Key__c = key;

        if (Schema.sObjectType.AdaSettings__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.isUpdateable() &&
            Schema.sObjectType.AdaSettings__c.fields.Private_Key__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.fields.Private_Key__c.isUpdateable()) {
            upsert adaSettings;
        }        
    }

    public static void setHmacKey(String key) {
        AdaSettings__c adaSettings = getSettings();
        
        // Immutable check: prevent key changes if already set
        if (String.isNotBlank(adaSettings.Hmac_Key__c)) {
            throw new SecurityException(HMAC_KEY_ALREADY_SET_ERROR);
        }

        if (String.isBlank(key)) {
            throw new IllegalArgumentException('Hmac key must not be blank');
        }

        Blob keyBlob;
        try {
            keyBlob = EncodingUtil.base64Decode(key);
        } catch(Exception e) {
            throw new IllegalArgumentException('Hmac key is not valid Base64');
        }

        if (keyBlob.size() != 32) {
            throw new IllegalArgumentException('Hmac key must be exactly 32 bytes (256 bits)');
        }
        
        adaSettings.Hmac_Key__c = key;

        if (Schema.sObjectType.AdaSettings__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.isUpdateable() &&
            Schema.sObjectType.AdaSettings__c.fields.Hmac_Key__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.fields.Hmac_Key__c.isUpdateable()) {
            upsert adaSettings;
        }        
    }

    public static void setBlockfrostProjectId(String blockfrostProjectId) {
        AdaSettings__c adaSettings = getSettings();
        adaSettings.BlockfrostProjectId__c = blockfrostProjectId;

        if (Schema.sObjectType.AdaSettings__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.isUpdateable() &&
            Schema.sObjectType.AdaSettings__c.fields.BlockfrostProjectId__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.fields.BlockfrostProjectId__c.isUpdateable()) {
            upsert adaSettings;
        }        
    }

    public static void validateEncryptionKey() {
        if (!isEncryptionKeySet()) {
            throw new SecurityException('Encryption key is not configured. Please set up the encryption key first.');
        }
        if (!isHmacKeySet()) {
            throw new SecurityException('Hmac key is not configured. Please set up the hmac key first.');
        }
    }
    
    public static Boolean isEncryptionKeySet() {
        AdaSettings__c adaSettings = getSettings();
        return String.isNotBlank(adaSettings.Private_Key__c);
    }

    public static Boolean isHmacKeySet() {
        AdaSettings__c adaSettings = getSettings();
        return String.isNotBlank(adaSettings.Hmac_Key__c);
    }
    
    public static Boolean isTransactionApprovalsEnabled() {
        AdaSettings__c adaSettings = getSettings();
        return adaSettings.Transaction_approvals_enabled__c != null ? adaSettings.Transaction_approvals_enabled__c : false;
    }
    
    public static void setTransactionApprovalsEnabled(Boolean isEnabled) {
        AdaSettings__c adaSettings = getSettings();
        adaSettings.Transaction_approvals_enabled__c = isEnabled;

        if (Schema.sObjectType.AdaSettings__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.isUpdateable() &&
            Schema.sObjectType.AdaSettings__c.fields.Transaction_approvals_enabled__c.isCreateable() &&
            Schema.sObjectType.AdaSettings__c.fields.Transaction_approvals_enabled__c.isUpdateable()) {
            upsert adaSettings;
        }
    }
    
    private static Boolean hasRequiredPermissions() {
        return hasPermissionSet('Ada_Wallet_Seed_Phrase');
    }
    
    private static Boolean hasPermissionSet(String permissionSetName) {
        try {
            if (!Schema.sObjectType.PermissionSetAssignment.isAccessible() || 
                !Schema.sObjectType.PermissionSet.isAccessible()) {
                return false;
            }
            
            Set<Id> userPermissionSets = new Set<Id>();
            for (PermissionSetAssignment psa : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId()]) {
                userPermissionSets.add(psa.PermissionSetId);
            }
            
            Id requiredPsId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1].Id;
            
            return userPermissionSets.contains(requiredPsId);
        } catch (Exception e) {            
            return false;
        }
    }
}
