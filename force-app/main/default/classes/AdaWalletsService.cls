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

    public static void setPrivateKey(String key) {
        AdaSettings__c adaSettings = getSettings();
        adaSettings.Private_Key__c = key;
        upsert adaSettings;
    }
}
