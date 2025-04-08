public with sharing class WalletSetController {
    @AuraEnabled
    public static Id createWalletSet(String walletName, String seedPhrase, String rootPrivateKey, String rootPublicKey) {
        try {
            Wallet_Set__c walletSet = new Wallet_Set__c();
            walletSet.Wallet_Name__c = walletName;
            walletSet.Seed_Phrase__c = seedPhrase;
            walletSet.Root_Private_Key__c = rootPrivateKey;
            walletSet.Root_Public_Key__c = rootPublicKey;
            insert walletSet;
            return walletSet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet Set: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Wallet_Set__c getWalletSetDetails(String walletRecordId) {
        try {
            Wallet__c wallet = WalletSelector.getWalletById(walletRecordId);
            if (wallet.Wallet_Set__c == null) {
                throw new AuraHandledException('No Wallet_Set__c record associated with this Wallet__c record.');
            }
            return WalletSetSelector.getWalletSetById(wallet.Wallet_Set__c);
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching Wallet_Set__c details: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateWallet(String walletId, String accountPublicKey, String accountPrivateKey) {
        try {
            Wallet__c wallet = WalletSelector.getWalletById(walletId);
            wallet.Account_Public_Key__c = accountPublicKey;
            wallet.Account_Private_Key__c = accountPrivateKey;
            update wallet;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating Wallet__c record: ' + e.getMessage());
        }
    }
}