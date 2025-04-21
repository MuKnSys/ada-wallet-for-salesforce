public with sharing class ADAWalletSettingsController {
    @AuraEnabled
    public static Map<String, String> getADAWalletSettings() {
        Map<String, String> result = new Map<String, String>();
        try {
            List<ADAWalletSettings__c> settings = [SELECT BlockfrostProjectId__c 
                                                   FROM ADAWalletSettings__c 
                                                   LIMIT 1];
            if (!settings.isEmpty()) {
                result.put('blockfrostProjectId', settings[0].BlockfrostProjectId__c != null ? settings[0].BlockfrostProjectId__c : '');
                System.debug('Retrieved BlockfrostProjectId__c: ' + settings[0].BlockfrostProjectId__c);
            } else {
                result.put('blockfrostProjectId', '');
                System.debug('No settings record found');
            }
        } catch (Exception e) {
            System.debug('Error retrieving settings: ' + e.getMessage());
            throw new AuraHandledException('Error retrieving settings: ' + e.getMessage());
        }
        return result;
    }

    @AuraEnabled
    public static void saveADAWalletSettings(String blockfrostProjectId) {
        try {
            System.debug('Saving BlockfrostProjectId__c: ' + blockfrostProjectId);
            List<ADAWalletSettings__c> existingSettings = [SELECT Id, BlockfrostProjectId__c 
                                                          FROM ADAWalletSettings__c 
                                                          LIMIT 1];
            ADAWalletSettings__c setting;
            if (!existingSettings.isEmpty()) {
                setting = existingSettings[0];
                System.debug('Existing record ID: ' + setting.Id + ', Current BlockfrostProjectId__c: ' + setting.BlockfrostProjectId__c);
            } else {
                setting = new ADAWalletSettings__c(Name = 'Default ADA Wallet Settings');
                System.debug('Creating new record');
            }
            setting.BlockfrostProjectId__c = blockfrostProjectId;
            upsert setting;
            System.debug('Upserted record ID: ' + setting.Id + ', New BlockfrostProjectId__c: ' + setting.BlockfrostProjectId__c);
        } catch (Exception e) {
            System.debug('Error saving settings: ' + e.getMessage());
            throw new AuraHandledException('Failed to save settings: ' + e.getMessage());
        }
    }
}