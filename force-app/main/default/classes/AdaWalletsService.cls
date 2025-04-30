public with sharing class AdaWalletsService {
    private static AdaSettings__c adaSettings;

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
        adaSettings.Private_Key__c = key;
        upsert adaSettings;
    }

    public static void setBlockfrostProjectId(String blockfrostProjectId) {
        AdaSettings__c adaSettings = getSettings();
        adaSettings.BlockfrostProjectId__c = blockfrostProjectId;
        upsert adaSettings;
    }
}
